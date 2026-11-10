using System.Data;
using System.Text.Json;
using Oracle.ManagedDataAccess.Client;
using Oracle.ManagedDataAccess.Types;
using Payroll.Api.Contracts;

namespace Payroll.Api.Data;

public sealed class OracleConfigurationRepository(OracleConnectionFactory factory, OracleFinanceRepository reader)
{
    private const string Package = "PAYROLL_APP.PKG_CONFIGURATION.";
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private static OracleParameter Text(string name, string? value) => new(name, OracleDbType.Varchar2)
        { Value = value is null ? DBNull.Value : value };

    public Task<List<Dictionary<string, object?>>> ReadAsync(long actor, string resource, long? employee, long? period, CancellationToken ct) =>
        reader.ReadAsync(Package + "read_data", actor, ct, Text("p_resource", resource),
            OracleFinanceRepository.Id("p_employee", employee), OracleFinanceRepository.Id("p_period", period));

    // Procedure names are selected by the controller, never supplied by the client.
    public async Task<long> CreateAsync(long actor, string operation, object payload, CancellationToken ct)
    {
        if (operation is not ("policy" or "allowance" or "entry" or "account" or "dependent"))
            throw new ArgumentOutOfRangeException(nameof(operation));
        using var connection = factory.CreateConnection();
        await connection.OpenAsync(ct);
        using var transaction = connection.BeginTransaction();
        using var command = connection.CreateCommand();
        command.CommandText = Package + "create_" + operation;
        command.CommandType = CommandType.StoredProcedure;
        command.BindByName = true;
        command.Parameters.Add(OracleFinanceRepository.Id("p_actor", actor));
        command.Parameters.Add(new OracleParameter("p_data", OracleDbType.Clob) { Value = JsonSerializer.Serialize(payload, JsonOptions) });
        var output = command.Parameters.Add("p_id", OracleDbType.Decimal);
        output.Direction = ParameterDirection.Output;
        await command.ExecuteNonQueryAsync(ct);
        if (output.Value is not OracleDecimal id || id.IsNull || !id.IsInt || !id.IsPositive)
            throw new FinancePortalException(500, "Oracle trả mã hồ sơ không hợp lệ; giao dịch chưa được xác nhận.");
        var result = checked((long)id.Value);
        transaction.Commit();
        return result;
    }

    public Task<bool> DecideAsync(long actor, string resource, long id, ConfigurationDecisionRequest request, CancellationToken ct) =>
        reader.WriteAsync(Package + "decide", actor, ct, Text("p_resource", resource), OracleFinanceRepository.Id("p_id", id),
            Text("p_decision", request.Decision), Text("p_reason", request.Reason?.Trim()));

    public Task<bool> EndPolicyAsync(long actor, long id, DateOnly end, string reason, CancellationToken ct) =>
        reader.WriteAsync(Package + "end_policy", actor, ct, OracleFinanceRepository.Id("p_policy", id),
            new OracleParameter("p_to", OracleDbType.Date) { Value = end.ToDateTime(TimeOnly.MinValue, DateTimeKind.Unspecified) },
            Text("p_reason", reason.Trim()));
}
