using System.Data;
using Oracle.ManagedDataAccess.Client;
using Payroll.Api.Contracts;

namespace Payroll.Api.Data;

public class OracleDepartmentRepository
{
    private readonly OracleConnectionFactory _connectionFactory;

    public OracleDepartmentRepository(
        OracleConnectionFactory connectionFactory)
    {
        _connectionFactory = connectionFactory;
    }

    public async Task<List<DepartmentListItem>> GetDepartmentsAsync(
        long actorId,
        CancellationToken cancellationToken)
    {
        using var connection = _connectionFactory.CreateConnection();
        await connection.OpenAsync(cancellationToken);

        using var command = connection.CreateCommand();
        command.CommandText = "PAYROLL_APP.PKG_HR_READ.list_departments";
        command.CommandType = CommandType.StoredProcedure;
        command.BindByName = true;

        command.Parameters.Add("p_actor", OracleDbType.Int64)
            .Value = actorId;

        command.Parameters.Add("p_rows", OracleDbType.RefCursor)
            .Direction = ParameterDirection.Output;

        using var reader = await command.ExecuteReaderAsync(cancellationToken);

        var departments = new List<DepartmentListItem>();

        while (await reader.ReadAsync(cancellationToken))
        {
            departments.Add(new DepartmentListItem
            {
                DepartmentId = reader.GetInt64(reader.GetOrdinal("DEPARTMENT_ID")),
                DepartmentCode = reader.GetString(reader.GetOrdinal("DEPARTMENT_CODE")),
                DepartmentName = reader.GetString(reader.GetOrdinal("DEPARTMENT_NAME"))
            });
        }

        return departments;
    }
}