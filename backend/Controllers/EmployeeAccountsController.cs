using System.Globalization;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Oracle.ManagedDataAccess.Client;
using Payroll.Api.Contracts;
using Payroll.Api.Data;
using Payroll.Api.Services;

namespace Payroll.Api.Controllers;

[ApiController, Authorize(Roles = "HR")]
[Route("api/employees/{employeeId:long}/account")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class EmployeeAccountsController(OracleEmployeeAccountRepository repository) : ControllerBase
{
    private long Actor() => long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier),
        NumberStyles.None, CultureInfo.InvariantCulture, out var id) && id > 0
        ? id : throw new PlatformException("Phiên đăng nhập không hợp lệ.", 401);

    [HttpGet]
    public Task<IActionResult> Get(long employeeId, CancellationToken ct) =>
        Execute(employeeId, async () => Ok(await repository.GetAsync(Actor(), employeeId, ct)));

    [HttpPost]
    public Task<IActionResult> Create(long employeeId, CreateEmployeeAccountRequest request, CancellationToken ct) =>
        Execute(employeeId, async () => StatusCode(201, await repository.CreateAsync(Actor(), employeeId, request, ct)));

    private async Task<IActionResult> Execute(long employee, Func<Task<IActionResult>> action)
    {
        if (employee <= 0) return BadRequest(new { message = "Mã nhân viên không hợp lệ." });
        try { return await action(); }
        catch (OracleException error) when (error.Number is >= 20700 and <= 20706)
        {
            var message = error.Number switch
            {
                20700 => "Không tìm thấy nhân viên.",
                20701 => "Nhân viên đã có tài khoản đăng nhập.",
                20702 => "Hồ sơ vừa thay đổi. Hãy tải lại trước khi cấp tài khoản.",
                20703 => "Chỉ cấp tài khoản cho nhân viên đang làm việc.",
                20704 => "Mã nhân viên hoặc số điện thoại chưa đáp ứng quy tắc tạo tài khoản.",
                20705 => "Ngày sinh phải trước ngày vào làm và trước ngày hiện tại.",
                _ => "Ngày sinh đã thay đổi. Hãy tải lại hồ sơ nhân viên."
            };
            return StatusCode(error.Number == 20700 ? 404 : 409, new { message });
        }
        catch (OracleException error) when (error.Number == 1)
        {
            return Conflict(new { message = "Nhân viên đã có tài khoản hoặc tên đăng nhập đã được sử dụng. Hãy tải lại và kiểm tra số điện thoại." });
        }
    }
}
