using System.Data;
using Oracle.ManagedDataAccess.Client;
using Payroll.Api.Contracts;

namespace Payroll.Api.Data;

public class OracleJobPositionRepository
{
    private readonly OracleConnectionFactory _connectionFactory;

    public OracleJobPositionRepository(
        OracleConnectionFactory connectionFactory)
    {
        _connectionFactory = connectionFactory;
    }

    public async Task<List<JobPositionListItem>> GetJobPositionsAsync(
        long actorId,
        CancellationToken cancellationToken)
    {
        using var connection = _connectionFactory.CreateConnection();
        await connection.OpenAsync(cancellationToken);

        using var command = connection.CreateCommand();
        command.CommandText = "PAYROLL_APP.PKG_HR_READ.list_job_positions";
        command.CommandType = CommandType.StoredProcedure;
        command.BindByName = true;

        command.Parameters.Add("p_actor", OracleDbType.Int64)
            .Value = actorId;

        command.Parameters.Add("p_rows", OracleDbType.RefCursor)
            .Direction = ParameterDirection.Output;

        using var reader = await command.ExecuteReaderAsync(cancellationToken);

        var jobPositions = new List<JobPositionListItem>();

        while (await reader.ReadAsync(cancellationToken))
        {
            jobPositions.Add(new JobPositionListItem
            {
                PositionId = reader.GetInt64(reader.GetOrdinal("POSITION_ID")),
                PositionCode = reader.GetString(reader.GetOrdinal("POSITION_CODE")),
                PositionName = reader.GetString(reader.GetOrdinal("POSITION_NAME"))
            });
        }

        return jobPositions;
    }
}