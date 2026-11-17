using System.Data;
using Microsoft.AspNetCore.Identity;
using Oracle.ManagedDataAccess.Client;
using Oracle.ManagedDataAccess.Types;
using Payroll.Api.Contracts;
using Payroll.Api.Services;

namespace Payroll.Api.Data;

public sealed class OracleEmployeeAccountRepository(
    OracleConnectionFactory factory, IPasswordHasher<AuthUser> hasher)
{
    public async Task<EmployeeAccountContext> GetAsync(long actor, long employee, CancellationToken ct)
    {
        using var connection = factory.CreateConnection();
        await connection.OpenAsync(ct);
        return await ReadContextAsync(connection, actor, employee, false, ct);
    }

    public async Task<CreatedEmployeeAccount> CreateAsync(
        long actor, long employee, CreateEmployeeAccountRequest request, CancellationToken ct)
    {
        using var connection = factory.CreateConnection();
        await connection.OpenAsync(ct);
        using var transaction = connection.BeginTransaction();
        var profile = await ReadContextAsync(connection, actor, employee, true, ct);
        if (profile.UserId is not null)
            throw new PlatformException("Nhân viên đã có tài khoản đăng nhập.");
        if (profile.RowVersion != request.RowVersion)
            throw new PlatformException("Hồ sơ vừa thay đổi. Hãy tải lại trước khi cấp tài khoản.");
        if (profile.Status != "ACTIVE" || profile.TerminationDate is not null)
            throw new PlatformException("Chỉ cấp tài khoản cho nhân viên đang làm việc.");

        var birthDate = request.BirthDate ?? throw new PlatformException("Vui lòng bổ sung ngày sinh.", 400);
        var today = DateOnly.FromDateTime(TimeZoneInfo.ConvertTimeBySystemTimeZoneId(DateTimeOffset.UtcNow, "Asia/Ho_Chi_Minh").DateTime);
        if (birthDate >= today || birthDate >= profile.HireDate)
            throw new PlatformException("Ngày sinh phải trước ngày vào làm và trước ngày hiện tại.", 400);
        if (profile.BirthDate is not null && profile.BirthDate != birthDate)
            throw new PlatformException("Ngày sinh đã có trong hồ sơ. Hãy chỉnh sửa hồ sơ nếu cần cập nhật.");

        var username = EmployeeAccountRules.Username(profile.EmployeeCode, request.PhoneNumber);
        var password = EmployeeAccountRules.InitialPassword(birthDate, profile.FullName);
        var hash = hasher.HashPassword(new AuthUser { Username = username }, password);
        using var command = connection.CreateCommand();
        command.BindByName = true;
        command.CommandType = CommandType.StoredProcedure;
        command.CommandText = "PAYROLL_APP.PKG_EMPLOYEE_ACCOUNTS.create_account";
        command.Parameters.Add("p_actor", OracleDbType.Int64).Value = actor;
        command.Parameters.Add("p_employee", OracleDbType.Int64).Value = employee;
        command.Parameters.Add("p_version", OracleDbType.Int64).Value = request.RowVersion;
        command.Parameters.Add("p_phone", OracleDbType.Varchar2).Value = request.PhoneNumber;
        command.Parameters.Add("p_birth", OracleDbType.Date).Value = birthDate.ToDateTime(TimeOnly.MinValue);
        command.Parameters.Add("p_username", OracleDbType.Varchar2).Value = username;
        command.Parameters.Add("p_hash", OracleDbType.Varchar2).Value = hash;
        var output = command.Parameters.Add("p_id", OracleDbType.Decimal);
        output.Direction = ParameterDirection.Output;
        await command.ExecuteNonQueryAsync(ct);
        var userId = checked((long)((OracleDecimal)output.Value).Value);
        transaction.Commit();
        return new CreatedEmployeeAccount(userId, username, password);
    }

    private static async Task<EmployeeAccountContext> ReadContextAsync(
        OracleConnection connection, long actor, long employee, bool forUpdate, CancellationToken ct)
    {
        using var command = connection.CreateCommand();
        command.BindByName = true;
        command.CommandType = CommandType.StoredProcedure;
        command.CommandText = "PAYROLL_APP.PKG_EMPLOYEE_ACCOUNTS.get_context";
        command.Parameters.Add("p_actor", OracleDbType.Int64).Value = actor;
        command.Parameters.Add("p_employee", OracleDbType.Int64).Value = employee;
        command.Parameters.Add("p_lock", OracleDbType.Int32).Value = forUpdate ? 1 : 0;
        command.Parameters.Add("p_rows", OracleDbType.RefCursor).Direction = ParameterDirection.Output;
        using var reader = await command.ExecuteReaderAsync(ct);
        if (!await reader.ReadAsync(ct))
            throw new PlatformException("Không tìm thấy nhân viên.", 404);
        return new EmployeeAccountContext(
            reader.GetInt64(0), reader.GetString(1), reader.GetString(2),
            reader.IsDBNull(3) ? null : DateOnly.FromDateTime(reader.GetDateTime(3)),
            DateOnly.FromDateTime(reader.GetDateTime(4)), reader.IsDBNull(5) ? null : reader.GetString(5),
            reader.GetString(6), reader.IsDBNull(7) ? null : DateOnly.FromDateTime(reader.GetDateTime(7)),
            reader.GetInt64(8), reader.IsDBNull(9) ? null : reader.GetInt64(9),
            reader.IsDBNull(10) ? null : reader.GetString(10), reader.IsDBNull(11) ? null : reader.GetString(11) == "Y");
    }
}
