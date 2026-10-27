using Microsoft.AspNetCore.Authorization;
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