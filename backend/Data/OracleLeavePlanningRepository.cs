using System.Data;
using System.Security.Cryptography;
using System.Text.Json;
using Oracle.ManagedDataAccess.Client;
using Oracle.ManagedDataAccess.Types;
using Payroll.Api.Contracts;
using Payroll.Api.Services;

namespace Payroll.Api.Data;

public sealed class OracleLeavePlanningRepository(OracleConnectionFactory factory)
{
    private static OracleCommand Command(OracleConnection connection, string operation, long actor, LeavePlanRequest request)
    {
        var command = connection.CreateCommand();
        command.BindByName = true;
        command.CommandType = CommandType.StoredProcedure;
        command.CommandText = "PAYROLL_APP.PKG_LEAVE_PLANNING." + operation;
        command.Parameters.Add("p_actor", OracleDbType.Int64).Value = actor;
        command.Parameters.Add("p_employee", OracleDbType.Int64).Value = request.EmployeeId;
        return command;
    }

    private static void AddScheduleParameters(OracleCommand command, LeavePlanRequest request)
    {
        command.Parameters.Add("p_from", OracleDbType.Date).Value = request.StartDate!.Value.ToDateTime(TimeOnly.MinValue);
        command.Parameters.Add("p_to", OracleDbType.Date).Value = request.LastDate!.Value.AddDays(1).ToDateTime(TimeOnly.MinValue);
        command.Parameters.Add("p_duration", OracleDbType.Varchar2).Value = request.Duration;
        command.Parameters.Add("p_minutes", OracleDbType.Int32).Value = request.Duration == "HOURS"
            ? checked((int)(request.HoursPerDay!.Value * 60)) : DBNull.Value;
    }

    public async Task<LeavePlanResponse> PreviewAsync(long actor, LeavePlanRequest request, CancellationToken ct)
    {
        using var connection = factory.CreateConnection();
        await connection.OpenAsync(ct);
        return await ReadPlanAsync(connection, actor, request, ct);
    }

    public async Task<long> SubmitAsync(long actor, ScheduledLeaveRequest request, CancellationToken ct)
    {
        using var connection = factory.CreateConnection();
        await connection.OpenAsync(ct);
        using var transaction = connection.BeginTransaction();
        using (var locked = Command(connection, "lock_plan", actor, request))
            await locked.ExecuteNonQueryAsync(ct);
        var plan = await ReadPlanAsync(connection, actor, request, ct);
        if (!plan.CanSubmit)
            throw new PlatformException(string.Join(" ", plan.Issues), 409);
        if (!string.Equals(plan.ScheduleToken, request.ScheduleToken, StringComparison.Ordinal))
            throw new PlatformException("Lịch làm việc hoặc hợp đồng đã thay đổi. Hãy tính lại thời gian nghỉ trước khi gửi.", 409);

        using var command = Command(connection, "submit", actor, request);
        AddScheduleParameters(command, request);
        command.Parameters.Add("p_type", OracleDbType.Int64).Value = request.LeaveTypeId;
        command.Parameters.Add("p_reason", OracleDbType.Varchar2).Value = request.Reason.Trim();
        var output = command.Parameters.Add("p_id", OracleDbType.Decimal);
        output.Direction = ParameterDirection.Output;
        await command.ExecuteNonQueryAsync(ct);
        var id = checked((long)((OracleDecimal)output.Value).Value);
        transaction.Commit();
        return id;
    }

    private static async Task<LeavePlanResponse> ReadPlanAsync(OracleConnection connection, long actor, LeavePlanRequest request, CancellationToken ct)
    {
        using var command = Command(connection, "preview", actor, request);
        AddScheduleParameters(command, request);
        command.Parameters.Add("p_rows", OracleDbType.RefCursor).Direction = ParameterDirection.Output;
        using var reader = await command.ExecuteReaderAsync(ct);
        var days = new List<LeavePlanDay>();
        while (await reader.ReadAsync(ct))
        {
            days.Add(new LeavePlanDay(DateOnly.FromDateTime(reader.GetDateTime(0)),
                reader.IsDBNull(1) ? null : reader.GetInt64(1), reader.IsDBNull(2) ? null : reader.GetInt64(2),
                reader.IsDBNull(3) ? null : reader.GetString(3), reader.IsDBNull(4) ? null : reader.GetString(4),
                reader.IsDBNull(5) ? null : reader.GetInt32(5), reader.IsDBNull(6) ? null : reader.GetInt32(6),
                reader.IsDBNull(7) ? null : reader.GetString(7)));
        }
        var issues = days.Where(day => day.IssueCode is not null).Select(day => IssueMessage(day.IssueCode!)).Distinct().ToList();
        if (days.Count != request.LastDate!.Value.DayNumber - request.StartDate!.Value.DayNumber + 1)
            issues.Add("Lịch hợp đồng bị thiếu hoặc chồng nhau. Vui lòng liên hệ nhân sự kiểm tra.");
        var total = days.Sum(day => day.LeaveMinutes ?? 0);
        if (total == 0 && issues.Count == 0)
            issues.Add("Khoảng đã chọn chỉ có ngày nghỉ hoặc ngày lễ, không cần gửi đơn nghỉ phép.");
        var bytes = JsonSerializer.SerializeToUtf8Bytes(new { actor, request.EmployeeId, request.StartDate, request.LastDate, request.Duration, request.HoursPerDay, days });
        var token = Convert.ToHexString(SHA256.HashData(bytes));
        return new LeavePlanResponse(days, days.Count(day => day.LeaveMinutes > 0),
            days.Count(day => day.LeaveMinutes == 0), total, issues, token, issues.Count == 0 && total > 0);
    }

    public static string IssueMessage(string code) => code switch
    {
        "OUTSIDE_EMPLOYMENT" => "Có ngày nghỉ nằm ngoài thời gian làm việc của nhân viên.",
        "MISSING_CONTRACT" => "Chưa có hợp đồng được duyệt phủ đủ khoảng nghỉ. Vui lòng liên hệ nhân sự.",
        "MISSING_CALENDAR" => "Lịch làm việc chưa được thiết lập đủ ngày. Vui lòng liên hệ nhân sự bổ sung lịch.",
        "FRACTIONAL_HALF" => "Giờ chuẩn của một ngày chưa chia được thành hai phần bằng phút nguyên. Hãy chọn nghỉ theo giờ hoặc liên hệ nhân sự.",
        "EXCEEDS_DAY" => "Số giờ xin nghỉ vượt giờ làm việc chuẩn của một ngày trong khoảng đã chọn.",
        _ => "Lịch làm việc chưa hợp lệ. Vui lòng liên hệ nhân sự."
    };
}
