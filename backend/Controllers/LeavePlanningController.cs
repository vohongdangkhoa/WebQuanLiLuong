using System.Globalization;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Oracle.ManagedDataAccess.Client;
using Payroll.Api.Contracts;
using Payroll.Api.Data;
using Payroll.Api.Services;

namespace Payroll.Api.Controllers;

[ApiController, Authorize(Roles = "HR,EMPLOYEE"), Route("api/hr/requests/leave")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class LeavePlanningController(OracleLeavePlanningRepository repository) : ControllerBase
{
    private long Actor() => long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier),
        NumberStyles.None, CultureInfo.InvariantCulture, out var actor) && actor > 0
        ? actor : throw new PlatformException("Phiên đăng nhập không hợp lệ.", 401);

    [HttpGet("preview")]
    public Task<IActionResult> Preview([FromQuery] LeavePlanRequest request, CancellationToken ct) =>
        Execute(async () => Ok(await repository.PreviewAsync(Actor(), request, ct)));

    [HttpPost("scheduled")]
    public Task<IActionResult> Submit([FromBody] ScheduledLeaveRequest request, CancellationToken ct) =>
        Execute(async () => {
            var id = await repository.SubmitAsync(Actor(), request, ct);
            return Ok(new { id, message = "Đã gửi đơn nghỉ phép chờ phê duyệt. Thời gian nghỉ được tính theo lịch làm việc." });
        });

    private async Task<IActionResult> Execute(Func<Task<IActionResult>> action)
    {
        try { return await action(); }
        catch (OracleException error) when (error.Number == 20404)
        { return NotFound(new { message = "Không tìm thấy nhân viên hoặc loại nghỉ đã chọn." }); }
        catch (OracleException error) when (error.Number == 20410)
        { return Conflict(new { message = "Khoảng nghỉ trùng với đơn đang chờ duyệt hoặc đã duyệt. Hãy kiểm tra danh sách đơn." }); }
        catch (OracleException error) when (error.Number is >= 20800 and <= 20803)
        { return BadRequest(new { message = "Thời lượng hoặc lịch nghỉ chưa hợp lệ. Hãy tính lại thời gian nghỉ và kiểm tra lý do." }); }
    }
}
