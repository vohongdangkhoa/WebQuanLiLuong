using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Oracle.ManagedDataAccess.Client;
using Payroll.Api.Data;
using System.Globalization;
using System.Security.Claims;

namespace Payroll.Api.Controllers;

[ApiController]
[Route("api/departments")]
[Authorize(Roles = "HR")]
public class DepartmentsController : ControllerBase
{
    private readonly OracleDepartmentRepository _departmentRepository;

    public DepartmentsController(
        OracleDepartmentRepository departmentRepository)
    {
        _departmentRepository = departmentRepository;
    }

    [HttpGet]
    [ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
    public async Task<IActionResult> GetDepartments(
        CancellationToken cancellationToken)
    {
        var actorIdText = User.FindFirstValue(ClaimTypes.NameIdentifier);

        if (!long.TryParse(
                actorIdText,
                NumberStyles.None,
                CultureInfo.InvariantCulture,
                out var actorId) ||
            actorId <= 0)
        {
            return Unauthorized();
        }

        try
        {
            var departments = await _departmentRepository.GetDepartmentsAsync(
                actorId,
                cancellationToken);

            return Ok(departments);
        }
        catch (OracleException ex) when (ex.Number == 20002)
        {
            return Forbid();
        }
    }
}