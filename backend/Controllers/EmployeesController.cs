using Microsoft.AspNetCore.Authorization;
using Payroll.Api.Contracts;
using Microsoft.AspNetCore.Mvc;
using Payroll.Api.Data;
using System.Globalization;
using System.Security.Claims;
using Oracle.ManagedDataAccess.Client;

namespace Payroll.Api.Controllers;

[ApiController]
[Route("api/employees")]
[Authorize(Roles = "HR")]
public class EmployeesController : ControllerBase
{
    private readonly OracleEmployeeRepository _employeeRepository;

    public EmployeesController(
        OracleEmployeeRepository employeeRepository)
    {
        _employeeRepository = employeeRepository;
    }
    [HttpGet]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public async Task<IActionResult> GetEmployees(
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
        var employees = await _employeeRepository.GetEmployeesAsync(
            actorId,
            cancellationToken);

        return Ok(employees);
    }
    catch (OracleException ex) when (ex.Number == 20002)
    {
        return Forbid();
    }
}
[HttpPost]
public async Task<IActionResult> CreateEmployee(
    [FromBody] CreateEmployeeRequest request,
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
        var employeeId = await _employeeRepository.CreateEmployeeAsync(
            actorId,
            request,
            cancellationToken);

        return StatusCode(StatusCodes.Status201Created, new
        {
            employeeId,
            message = "Đã thêm nhân viên."
        });
    }
    catch (OracleException ex) when (ex.Number == 20002)
{
    return Forbid();
}
catch (OracleException ex)
    when (ex.Number is 20300 or 20301 or 20302)
{
    var message = ex.Number switch
    {
        20300 => "Mã nhân viên là bắt buộc và tối đa 30 ký tự.",
        20301 => "Họ tên là bắt buộc và tối đa 150 ký tự.",
        _ => "Ngày vào làm không hợp lệ."
    };

    return BadRequest(new { message });
}
catch (OracleException ex)
    when (ex.Number == 1 &&
          ex.Message.Contains(
              "UQ_06_01",
              StringComparison.OrdinalIgnoreCase))
{
    return Conflict(new
    {
        message = "Mã nhân viên đã tồn tại. Vui lòng nhập mã khác."
    });
}
catch (OracleException ex)
    when (ex.Number is 20003 or 20006)
{
    return Conflict(new
    {
        message = "Chưa thể thêm nhân viên vì kỳ lương liên quan đã khóa, đã chốt hoặc đang xử lý."
    });
}
catch (OracleException ex) when (ex.Number == 54)
{
    return StatusCode(StatusCodes.Status503ServiceUnavailable, new
    {
        message = "Dữ liệu đang được xử lý bởi thao tác khác. Vui lòng thử lại sau."
    });
}
}
}

/* - [ApiController]: bật cách xử lý dành cho API.
- [Route("api/employees")]: các API trong lớp có đường dẫn bắt đầu bằng /api/employees.
- [Authorize(Roles = "HR")]: yêu cầu người dùng đã đăng nhập và có quyền Nhân sự.
- _employeeRepository: giữ lớp đọc nhân viên từ Oracle.
- Hàm khởi tạo nhận repository do ASP.NET cung cấp nhờ dòng AddScoped vừa đăng ký.
Bước kế mình sẽ thêm hàm GET, để controller trả danh sách nhân viên. */



/* [HttpGet]: tạo API GET /api/employees.
ResponseCache: yêu cầu trình duyệt không lưu kết quả vào bộ nhớ đệm.
NameIdentifier: lấy mã tài khoản từ phiên đăng nhập để truyền xuống Oracle.
TryParse: kiểm tra mã tài khoản là số nguyên dương; không hợp lệ thì trả 401.
GetEmployeesAsync(...): gọi lớp đọc Oracle, rồi Ok(employees) trả danh sách dưới dạng JSON.
catch ... 20002: nếu Oracle báo tài khoản không đủ quyền, trả 403 qua Forbid(). */

/* 
- [HttpPost]: nhận yêu cầu thêm nhân viên tại /api/employees.
- [FromBody]: đọc JSON React gửi vào CreateEmployeeRequest. Các điều kiện [Required], [StringLength] được kiểm tra nhờ [ApiController] đã có trên lớp.
- NameIdentifier: lấy mã tài khoản đang đăng nhập để biết ai thực hiện thao tác.
- CreateEmployeeAsync(...): gọi hàm xuống Oracle bạn vừa viết.
- 201 Created: báo tạo thành công, kèm ID nhân viên mới.
- Forbid(): trả 403 nếu Oracle báo tài khoản không đủ quyền.
Quyền HR đã được đặt trên cả lớp nên hàm mới cũng áp dụng quyền đó. */

/* when (...): chỉ xử lý khi số lỗi khớp điều kiện.
or: nghĩa là hoặc.
switch: chọn thông báo tương ứng với từng số lỗi.
UQ_06_01: tên quy tắc trong database yêu cầu mã nhân viên không được trùng. */