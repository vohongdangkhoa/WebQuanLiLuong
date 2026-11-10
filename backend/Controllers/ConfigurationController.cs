using System.Globalization;
using System.Security.Claims;
using System.Text;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Oracle.ManagedDataAccess.Client;
using Payroll.Api.Contracts;
using Payroll.Api.Data;
using Payroll.Api.Services;

namespace Payroll.Api.Controllers;

[ApiController]
[Route("api/configuration")]
[Authorize(Roles = "HR,PAYROLL,DIRECTOR,EMPLOYEE")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class ConfigurationController(OracleConfigurationRepository repository, BankSecurityService security,
    ILogger<ConfigurationController> logger) : ControllerBase
{
    private long Actor()
    {
        if (!long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), NumberStyles.None, CultureInfo.InvariantCulture, out var actor) || actor <= 0)
            throw new FinancePortalException(401, "Phiên đăng nhập không hợp lệ.");
        return actor;
    }
    private static long Positive(long value) => value > 0 ? value : throw new FinancePortalException(400, "Mã hồ sơ phải là số nguyên dương.");
    private static long? Optional(long? value) => value.HasValue ? Positive(value.Value) : null;
    private async Task<IActionResult> Guard(Func<Task<IActionResult>> action)
    {
        try { return await action(); }
        catch (FinancePortalException ex) { return StatusCode(ex.StatusCode, new { message = ex.Message }); }
        catch (OracleException ex)
        {
            var error = ex.Number switch
            {
                20700 or 2290 or 1400 or 12899 => (400, "Dữ liệu chưa hợp lệ. Kiểm tra ngày hiệu lực, số tiền, loại khoản và các trường bắt buộc."),
                20704 or 1403 => (404, "Không tìm thấy nhân viên hoặc hồ sơ liên quan."),
                20703 => (409, "Người tạo hồ sơ không được tự phê duyệt hoặc từ chối hồ sơ của mình."),
                20705 => (409, "Hồ sơ không còn ở trạng thái chờ duyệt. Hãy tải lại danh sách."),
                20706 => (409, "Khoảng hiệu lực bị chồng. Kiểm tra phiên bản chính sách, phụ cấp hoặc người phụ thuộc đã đăng ký."),
                20708 => (400, "Cần tệp minh chứng PDF, PNG hoặc JPEG thực tế do chính tài khoản này tải lên."),
                20709 => (409, "Định danh người phụ thuộc đã được đăng ký với thông tin khác. Cần kiểm tra lại họ tên và ngày sinh."),
                _ => FinanceErrors.Describe(ex.Number)
            };
            logger.LogWarning("Configuration operation failed, Oracle code {Code}, trace {Trace}", ex.Number, HttpContext.TraceIdentifier);
            return StatusCode(error.Item1, new { message = error.Item2 });
        }
        catch (OverflowException) { return StatusCode(500, new { message = "Mã Oracle vượt giới hạn; giao dịch chưa được xác nhận." }); }
    }

    [HttpGet("catalogs")]
    public Task<IActionResult> Catalogs(CancellationToken ct) => Guard(async () =>
    {
        var actor = Actor();
        var employees = await repository.ReadAsync(actor, "employees", null, null, ct);
        var manager = User.IsInRole("HR") || User.IsInRole("PAYROLL") || User.IsInRole("DIRECTOR");
        var periods = manager ? await repository.ReadAsync(actor, "periods", null, null, ct) : [];
        var components = manager ? await repository.ReadAsync(actor, "components", null, null, ct) : [];
        var deductionAccounts = manager ? await repository.ReadAsync(actor, "accounts", null, null, ct) : [];
        return Ok(new { employees, periods, components, deductionAccounts });
    });

    [HttpGet("policies"), Authorize(Roles = "HR,PAYROLL,DIRECTOR")]
    public Task<IActionResult> Policies(CancellationToken ct) => Guard(async () => Ok(await repository.ReadAsync(Actor(), "policies", null, null, ct)));

    [HttpGet("policies/{id:long}/brackets"), Authorize(Roles = "HR,PAYROLL,DIRECTOR")]
    public Task<IActionResult> Brackets(long id, CancellationToken ct) => Guard(async () => Ok(await repository.ReadAsync(Actor(), "brackets", null, Positive(id), ct)));

    [HttpGet("allowances"), Authorize(Roles = "HR,PAYROLL,DIRECTOR")]
    public Task<IActionResult> Allowances([FromQuery] long? employeeId, CancellationToken ct) => Guard(async () => Ok(await repository.ReadAsync(Actor(), "allowances", Optional(employeeId), null, ct)));

    [HttpGet("entries"), Authorize(Roles = "HR,PAYROLL,DIRECTOR")]
    public Task<IActionResult> Entries([FromQuery] long? employeeId, [FromQuery] long? periodId, CancellationToken ct) => Guard(async () => Ok(await repository.ReadAsync(Actor(), "entries", Optional(employeeId), Optional(periodId), ct)));

    [HttpGet("dependents")]
    public Task<IActionResult> Dependents([FromQuery] long? employeeId, CancellationToken ct) => Guard(async () => Ok(await repository.ReadAsync(Actor(), "dependents", Optional(employeeId), null, ct)));

    [HttpGet("deduction-accounts"), Authorize(Roles = "HR,PAYROLL,DIRECTOR")]
    public Task<IActionResult> Accounts(CancellationToken ct) => Guard(async () => Ok(await repository.ReadAsync(Actor(), "accounts", null, null, ct)));

    [HttpPost("policies"), Authorize(Roles = "PAYROLL")]
    public Task<IActionResult> CreatePolicy(CreatePolicyRequest request, CancellationToken ct) => Create("policy", request, "Đã tạo chính sách và bậc thuế chờ duyệt.", ct);

    [HttpPost("allowances"), Authorize(Roles = "HR,PAYROLL")]
    public Task<IActionResult> CreateAllowance(CreateAllowanceRequest request, CancellationToken ct) => Create("allowance", request, "Đã tạo phụ cấp chờ duyệt.", ct);

    [HttpPost("entries"), Authorize(Roles = "HR,PAYROLL")]
    public Task<IActionResult> CreateEntry(CreateConfigurationEntryRequest request, CancellationToken ct) => Create("entry", request, "Đã tạo khoản cộng/trừ chờ duyệt.", ct);

    [HttpPost("deduction-accounts"), Authorize(Roles = "PAYROLL")]
    public Task<IActionResult> CreateAccount(CreateDeductionAccountRequest request, CancellationToken ct) => Create("account", request, "Đã mở tài khoản theo dõi khấu trừ.", ct);

    [HttpPost("dependents"), Authorize(Roles = "HR,EMPLOYEE")]
    public Task<IActionResult> CreateDependent(CreateDependentRequest request, CancellationToken ct) => Guard(async () =>
    {
        var normalized = request.Identity.Normalize(NormalizationForm.FormKC).Trim().ToUpperInvariant();
        if (string.IsNullOrWhiteSpace(normalized)) return BadRequest(new { message = "Vui lòng nhập định danh người phụ thuộc." });
        var id = await repository.CreateAsync(Actor(), "dependent", new
        {
            request.EmployeeId, identityHmac = security.Fingerprint("Dependent", normalized), fullName = request.FullName.Trim(),
            request.BirthDate, request.ValidFrom, request.ValidTo, request.DocumentId
        }, ct);
        return StatusCode(201, new { id, message = "Đã đăng ký người phụ thuộc chờ xác minh." });
    });

    private Task<IActionResult> Create(string resource, object request, string message, CancellationToken ct) => Guard(async () =>
        StatusCode(201, new { id = await repository.CreateAsync(Actor(), resource, request, ct), message }));

    [HttpPost("{resource:regex(^(policies|allowances|entries|dependents)$)}/{id:long}/decision"), Authorize(Roles = "DIRECTOR")]
    public Task<IActionResult> Decide(string resource, long id, ConfigurationDecisionRequest request, CancellationToken ct) => Guard(async () =>
    {
        await repository.DecideAsync(Actor(), resource, Positive(id), request, ct);
        return Ok(new { message = request.Decision == "APPROVE" ? "Đã phê duyệt hồ sơ." : "Đã từ chối hồ sơ." });
    });

    [HttpPost("policies/{id:long}/end"), Authorize(Roles = "DIRECTOR")]
    public Task<IActionResult> EndPolicy(long id, EndPolicyRequest request, CancellationToken ct) => Guard(async () =>
    {
        if (request.ValidTo is not DateOnly end) return BadRequest(new { message = "Vui lòng chọn ngày kết thúc phiên bản." });
        await repository.EndPolicyAsync(Actor(), Positive(id), end, request.Reason, ct);
        return Ok(new { message = "Đã kết thúc khoảng hiệu lực của phiên bản chính sách." });
    });
}
