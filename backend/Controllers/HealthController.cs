using Microsoft.AspNetCore.Mvc;
using Payroll.Api.Data;
using Oracle.ManagedDataAccess.Client;
namespace Payroll.Api.Controllers;
[ApiController]
[Route("api/health")]
public class HealthController : ControllerBase
{
    private readonly OracleConnectionFactory _connectionFactory;

public HealthController(OracleConnectionFactory connectionFactory)
{
    _connectionFactory = connectionFactory;
}
    [HttpGet]
    public IActionResult Get()
    {
        return Ok(new { status = "ok" });
    }
    [HttpGet("database")]
public async Task<IActionResult> GetDatabase(CancellationToken cancellationToken)
{
    try
    {
        using var connection = _connectionFactory.CreateConnection();
        await connection.OpenAsync(cancellationToken);

        using var command = connection.CreateCommand();
        command.CommandText = "SELECT 1 FROM dual";

        await command.ExecuteScalarAsync(cancellationToken);

        return Ok(new
        {
            status = "ok",
            database = "connected"
        });
    }
    catch (OracleException)
    {
        return StatusCode(503, new
        {
            status = "error",
            message = "Không kết nối được Oracle."
        });
    }
    catch (InvalidOperationException)
    {
        return StatusCode(503, new
        {
            status = "error",
            message = "Kiểm tra lại cấu hình kết nối Oracle."
        });
    }
}
}