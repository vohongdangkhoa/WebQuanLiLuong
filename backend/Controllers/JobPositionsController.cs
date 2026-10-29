using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Oracle.ManagedDataAccess.Client;
using Payroll.Api.Data;
using System.Globalization;
using System.Security.Claims;

namespace Payroll.Api.Controllers;

[ApiController]
[Route("api/job-positions")]
[Authorize(Roles = "HR")]
public class JobPositionsController : ControllerBase
{
    private readonly OracleJobPositionRepository _jobPositionRepository;

    public JobPositionsController(
        OracleJobPositionRepository jobPositionRepository)
    {
        _jobPositionRepository = jobPositionRepository;
    }

    [HttpGet]
    [ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
    public async Task<IActionResult> GetJobPositions(
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
            var jobPositions = await _jobPositionRepository.GetJobPositionsAsync(
                actorId,
                cancellationToken);

            return Ok(jobPositions);
        }
        catch (OracleException ex) when (ex.Number == 20002)
        {
            return Forbid();
        }
    }
}