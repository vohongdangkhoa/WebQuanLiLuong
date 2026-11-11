using Microsoft.AspNetCore.Mvc;
using Oracle.ManagedDataAccess.Client;
using Payroll.Api.Data;
using System.Globalization;

namespace Payroll.Api.Controllers;

[ApiController]
[Route("api/health")]
public class HealthController(OracleConnectionFactory connectionFactory, ILogger<HealthController> logger) : ControllerBase
{
    [HttpGet]
    public IActionResult Get() => Ok(new { status = "ok", application = "HRFlow" });

    [HttpGet("database")]
    [ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
    public async Task<IActionResult> GetDatabase(CancellationToken cancellationToken)
    {
        try
        {
            using var connection = connectionFactory.CreateConnection();
            await connection.OpenAsync(cancellationToken);

            using var command = connection.CreateCommand();
            command.CommandText = """
                SELECT COUNT(*)
                FROM all_objects
                WHERE owner = 'PAYROLL_APP' AND object_type = 'PACKAGE' AND status = 'VALID'
                  AND object_name IN (
                    'PKG_AUTH', 'PKG_HR_READ', 'PKG_HR_WRITE', 'PKG_HR_CORE', 'PKG_HR_PORTAL', 'PKG_PLATFORM',
                    'PKG_FINANCE_PORTAL', 'PKG_CONFIGURATION', 'PKG_PAYROLL_CORE', 'PKG_PAYROLL_READ',
                    'PKG_REQUESTS', 'PKG_PAYMENT')
                """;
            const int requiredPackages = 12;
            var available = Convert.ToInt32(await command.ExecuteScalarAsync(cancellationToken), CultureInfo.InvariantCulture);
            if (available != requiredPackages)
            {
                logger.LogWarning("Oracle readiness check found {Available} of {Required} packages", available, requiredPackages);
                return StatusCode(503, new
                {
                    status = "error",
                    message = "Oracle đã kết nối nhưng thiếu package nghiệp vụ hoặc quyền thực thi."
                });
            }
            return Ok(new { status = "ok", database = "connected", packages = "available" });
        }
        catch (OracleException error)
        {
            logger.LogWarning("Oracle readiness check failed with code {Code}", error.Number);
            return StatusCode(503, new { status = "error", message = "Không kiểm tra được kết nối Oracle." });
        }
        catch (InvalidOperationException)
        {
            return StatusCode(503, new { status = "error", message = "Kiểm tra lại cấu hình kết nối Oracle." });
        }
    }
}
