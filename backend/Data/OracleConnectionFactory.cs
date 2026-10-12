using Microsoft.Extensions.Configuration;
using Oracle.ManagedDataAccess.Client;

namespace Payroll.Api.Data;

public class OracleConnectionFactory
{
    private readonly IConfiguration _configuration;

    public OracleConnectionFactory(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    public OracleConnection CreateConnection()
    {
        var connectionString = _configuration.GetConnectionString("Oracle");

        if (string.IsNullOrWhiteSpace(connectionString))
        {
            throw new InvalidOperationException("Chưa cấu hình kết nối Oracle.");
        }

        return new OracleConnection(connectionString);
    }
}