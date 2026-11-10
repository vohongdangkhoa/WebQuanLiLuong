using System.Data;
using System.Globalization;
using Oracle.ManagedDataAccess.Client;
using Oracle.ManagedDataAccess.Types;

namespace Payroll.Api.Data;

public sealed class OraclePlatformRepository(OracleConnectionFactory factory)
{
    public async Task<List<Dictionary<string, object?>>> ReadAsync(string procedure, long actor,
        CancellationToken token, params (string Name, OracleDbType Type, object? Value)[] arguments)
    {
        using var connection = factory.CreateConnection();
        await connection.OpenAsync(token);
        using var command = connection.CreateCommand();
        command.CommandText = "PAYROLL_APP.PKG_PLATFORM." + procedure;
        command.CommandType = CommandType.StoredProcedure;
        command.BindByName = true;
        command.Parameters.Add("p_actor", OracleDbType.Int64).Value = actor;
        foreach (var (name, type, value) in arguments)
            command.Parameters.Add(name, type).Value = value ?? DBNull.Value;
        command.Parameters.Add("p_rows", OracleDbType.RefCursor).Direction = ParameterDirection.Output;
        using var reader = await command.ExecuteReaderAsync(token);
        var rows = new List<Dictionary<string, object?>>();
        while (await reader.ReadAsync(token))
        {
            var row = new Dictionary<string, object?>();
            for (var i = 0; i < reader.FieldCount; i++)
            {
                var parts = reader.GetName(i).ToLowerInvariant().Split('_');
                var key = parts[0] + string.Concat(parts.Skip(1).Select(p => char.ToUpperInvariant(p[0]) + p[1..]));
                object? value = reader.IsDBNull(i) ? null :
                    reader.GetProviderSpecificValue(i) is OracleTimeStampTZ timestamp
                        ? timestamp : reader.GetValue(i);
                value = value switch
                {
                    OracleDecimal number => number.Value,
                    OracleClob clob => clob.Value,
                    OracleTimeStampTZ stamp => DateTime.SpecifyKind(
                        stamp.ToUniversalTime().Value, DateTimeKind.Utc).ToString("O", CultureInfo.InvariantCulture),
                    DateTime date => date.ToString("yyyy-MM-ddTHH:mm:ss", CultureInfo.InvariantCulture),
                    _ => value
                };
                row[key] = value;
            }
            rows.Add(row);
        }
        return rows;
    }
    public async Task<decimal?> WriteAsync(string procedure, long actor, CancellationToken token,
        string? output, params (string Name, OracleDbType Type, object? Value)[] arguments)
    {
        using var connection = factory.CreateConnection();
        await connection.OpenAsync(token);
        using var transaction = connection.BeginTransaction();
        using var command = connection.CreateCommand();
        command.CommandText = "PAYROLL_APP.PKG_PLATFORM." + procedure;
        command.CommandType = CommandType.StoredProcedure;
        command.BindByName = true;
        command.Parameters.Add("p_actor", OracleDbType.Int64).Value = actor;
        foreach (var (name, type, value) in arguments)
            command.Parameters.Add(name, type).Value = value ?? DBNull.Value;
        OracleParameter? result = null;
        if (output is not null)
        {
            result = command.Parameters.Add(output, OracleDbType.Decimal);
            result.Direction = ParameterDirection.Output;
        }
        await command.ExecuteNonQueryAsync(token);
        var number = result is null ? (decimal?)null : ((OracleDecimal)result.Value).Value;
        transaction.Commit();
        return number;
    }
}
