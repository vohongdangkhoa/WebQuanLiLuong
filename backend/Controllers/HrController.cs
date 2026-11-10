using System.Globalization;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Oracle.ManagedDataAccess.Client;
using Payroll.Api.Contracts;
using Payroll.Api.Data;
using static Payroll.Api.Data.OracleHrRepository;

namespace Payroll.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/hr")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class HrController(OracleHrRepository repository) : ControllerBase
{
    [HttpGet("catalogs")]
    public Task<IActionResult> Catalogs(CancellationToken ct) => Execute(async actor =>
    {
        var data = new Dictionary<string, object?>();
        foreach (var resource in new[] { "employees", "departments", "positions", "calendars", "shifts", "leaveTypes", "periods" })
            data[resource] = await repository.ReadAsync(actor, resource, null, null, ct);
        return Ok(data);
    });

    [HttpGet("organization/{kind:regex(^(departments|positions)$)}")]
    [Authorize(Roles = "HR")]
    public Task<IActionResult> OrganizationCatalog(string kind, CancellationToken ct) =>
        Read(string.Equals(kind, "departments", StringComparison.OrdinalIgnoreCase) ? "departmentCatalog" : "positionCatalog", null, null, ct);

    [HttpPost("organization/{kind:regex(^(departments|positions)$)}")]
    [Authorize(Roles = "HR")]
    public Task<IActionResult> SaveOrganizationCatalog(string kind, OrganizationCatalogRequest request, CancellationToken ct) =>
        Write("PAYROLL_APP.PKG_HR_PORTAL.save_organization_catalog",
            [Text("p_kind", kind.ToLowerInvariant()), Number("p_existing", request.Id), Text("p_code", request.Code.Trim()),
             Text("p_name", request.Name.Trim()), Text("p_active", request.IsActive)], true,
            "Đã lưu danh mục tổ chức.", ct);

    [HttpGet("attendance")]
    public Task<IActionResult> Attendance([FromQuery] long? periodId, [FromQuery] long? employeeId, CancellationToken ct) =>
        Read("attendance", periodId, employeeId, ct);

    [HttpPost("attendance")]
    [Authorize(Roles = "HR")]
    public Task<IActionResult> SaveAttendance([FromBody] HrAttendanceRequest request, CancellationToken ct) => Execute(async actor =>
    {
        if (!request.Certified)
            return BadRequest(new { message = "HR cần xác nhận đã đối chiếu dữ liệu công, nghỉ phép và ngày lễ trước khi lưu." });
        await repository.WriteAsync(actor, "PAYROLL_APP.PKG_HR_CORE.save_day", [
            Number("p_period", request.PeriodId), Number("p_employee", request.EmployeeId), Day("p_date", request.WorkDate),
            Number("p_worked", request.WorkedMinutes), Number("p_leave", request.LeaveMinutes), Number("p_holiday", request.HolidayMinutes)], false, ct);
        return Ok(new { message = "Đã lưu và xác nhận công trong ngày." });
    });

    [HttpPost("attendance/lock")]
    [Authorize(Roles = "HR")]
    public Task<IActionResult> Lock([FromBody] HrPeriodRequest request, CancellationToken ct) =>
        Write("PAYROLL_APP.PKG_HR_CORE.lock_timesheet", [Number("p_period", request.PeriodId)], false, "Đã chốt công kỳ lương.", ct);

    [HttpPost("attendance/reopen")]
    [Authorize(Roles = "HR")]
    public Task<IActionResult> Reopen([FromBody] HrReopenRequest request, CancellationToken ct) =>
        Write("PAYROLL_APP.PKG_HR_CORE.reopen_timesheet", [Number("p_period", request.PeriodId), Text("p_reason", request.Reason)], false, "Đã mở lại công và ghi nhận lý do.", ct);

    [HttpPost("calendar/month")]
    [Authorize(Roles = "HR")]
    public Task<IActionResult> Calendar([FromBody] HrCalendarRequest request, CancellationToken ct) =>
        Write("PAYROLL_APP.PKG_HR_PORTAL.prepare_calendar", [Number("p_calendar", request.CalendarId), Day("p_month", request.MonthDate)], false,
            "Đã bổ sung các ngày còn thiếu: thứ Hai–thứ Sáu 480 phút, cuối tuần 0 phút. Các ngày đã có được giữ nguyên.", ct);

    [HttpGet("calendar")]
    [Authorize(Roles = "HR")]
    public Task<IActionResult> CalendarDays([FromQuery] long calendarId, [FromQuery] DateOnly? monthDate, CancellationToken ct) =>
        Execute(async actor => Ok(await repository.ReadCalendarAsync(actor, calendarId, monthDate, ct)));

    [HttpPut("calendar/day")]
    [Authorize(Roles = "HR")]
    public Task<IActionResult> CalendarDay([FromBody] HrCalendarDayRequest request, CancellationToken ct) =>
        Write("PAYROLL_APP.PKG_HR_PORTAL.save_calendar_day", [Number("p_calendar", request.CalendarId), Day("p_date", request.WorkDate),
            Text("p_type", request.DayType), Number("p_minutes", request.StandardMinutes)], false, "Đã cập nhật loại ngày và phút chuẩn trong lịch làm việc.", ct);

    [HttpGet("requests")]
    public Task<IActionResult> Requests([FromQuery] long? employeeId, CancellationToken ct) => Execute(async actor =>
    {
        return Ok(new
        {
            leaves = await repository.ReadAsync(actor, "leaves", null, employeeId, ct),
            overtime = await repository.ReadAsync(actor, "overtime", null, employeeId, ct),
            corrections = await repository.ReadAsync(actor, "corrections", null, employeeId, ct),
            balances = await repository.ReadAsync(actor, "balances", null, employeeId, ct)
        });
    });

    [HttpPost("requests/leave")]
    [Authorize(Roles = "HR,EMPLOYEE")]
    public Task<IActionResult> CreateLeave([FromBody] HrLeaveRequest request, CancellationToken ct) =>
        Write("PAYROLL_APP.PKG_HR_PORTAL.create_leave", [Number("p_employee", request.EmployeeId), Number("p_type", request.LeaveTypeId),
            Day("p_from", request.StartDate), Day("p_to", request.EndDate), Number("p_minutes", request.MinutesPerDay), Text("p_reason", request.Reason)], true,
            "Đã gửi đơn nghỉ phép chờ phê duyệt.", ct);

    [HttpPost("requests/leave/{id:long}/decision")]
    [Authorize(Roles = "HR")]
    public Task<IActionResult> DecideLeave(long id, [FromBody] HrDecisionRequest request, CancellationToken ct) =>
        Write("PAYROLL_APP.PKG_REQUESTS.decide_leave", [Number("p_leave", ValidId(id)), Text("p_decision", request.Decision), Text("p_reason", request.Reason)], false,
            "Đã xử lý đơn nghỉ phép.", ct);

    [HttpPost("leave-balances")]
    [Authorize(Roles = "HR")]
    public Task<IActionResult> GrantLeave([FromBody] HrLeaveCreditRequest request, CancellationToken ct) =>
        Write("PAYROLL_APP.PKG_HR_PORTAL.grant_leave", [Number("p_employee", request.EmployeeId), Number("p_type", request.LeaveTypeId),
            Day("p_date", request.EffectiveDate), Number("p_minutes", request.Minutes), Text("p_reason", request.Reason), Text("p_key", request.RequestKey)], true,
            "Đã cấp số phút phép và ghi sổ phép.", ct);

    [HttpPost("requests/overtime")]
    [Authorize(Roles = "HR,EMPLOYEE")]
    public Task<IActionResult> CreateOvertime([FromBody] HrOvertimeRequest request, CancellationToken ct) => Execute(async actor =>
    {
        var id = await repository.WriteAsync(actor, "PAYROLL_APP.PKG_HR_PORTAL.create_overtime", [Number("p_employee", request.EmployeeId),
            Time("p_from", request.StartsAt), Time("p_to", request.EndsAt), Text("p_reason", request.Reason)], true, ct);
        return Ok(new { id, message = "Đã gửi đơn tăng ca chờ phê duyệt." });
    });

    [HttpPost("requests/overtime/{id:long}/approve")]
    [Authorize(Roles = "HR")]
    public Task<IActionResult> ApproveOvertime(long id, [FromBody] HrOvertimeApprovalRequest request, CancellationToken ct) =>
        Write("PAYROLL_APP.PKG_REQUESTS.approve_ot", [Number("p_ot", ValidId(id)), Number("p_minutes", request.Minutes)], false,
            "Đã duyệt số phút tăng ca. Cần xác nhận thời gian thực làm sau đó.", ct);

    [HttpPost("requests/overtime/{id:long}/confirm")]
    [Authorize(Roles = "HR")]
    public Task<IActionResult> ConfirmOvertime(long id, [FromBody] HrOvertimeConfirmationRequest request, CancellationToken ct) => Execute(async actor =>
    {
        await repository.WriteAsync(actor, "PAYROLL_APP.PKG_REQUESTS.confirm_ot", [Number("p_ot", ValidId(id)),
            Time("p_actual_start", request.ActualStart), Time("p_actual_end", request.ActualEnd)], false, ct);
        return Ok(new { message = "Đã xác nhận thời gian tăng ca thực tế." });
    });

    [HttpPost("requests/overtime/{id:long}/reject")]
    [Authorize(Roles = "HR")]
    public Task<IActionResult> RejectOvertime(long id, [FromBody] HrReasonRequest request, CancellationToken ct) =>
        Write("PAYROLL_APP.PKG_HR_PORTAL.reject_overtime", [Number("p_ot", ValidId(id)), Text("p_reason", request.Reason)], false,
            "Đã từ chối đơn tăng ca.", ct);

    [HttpPost("requests/correction")]
    [Authorize(Roles = "HR,PAYROLL,EMPLOYEE")]
    public Task<IActionResult> CreateCorrection([FromBody] HrCorrectionRequest request, CancellationToken ct) =>
        Write("PAYROLL_APP.PKG_HR_PORTAL.create_correction", [Number("p_period", request.PeriodId), Number("p_employee", request.EmployeeId),
            Text("p_source", request.SourceType), Number("p_source_id", request.SourceId), Text("p_reason", request.Reason)], true,
            "Đã gửi yêu cầu điều chỉnh cho bộ phận nhân sự.", ct);

    [HttpPost("requests/correction/{id:long}/resolve")]
    [Authorize(Roles = "HR")]
    public Task<IActionResult> ResolveCorrection(long id, [FromBody] HrReasonRequest request, CancellationToken ct) =>
        Write("PAYROLL_APP.PKG_HR_PORTAL.resolve_correction", [Number("p_request", ValidId(id)), Text("p_reason", request.Reason)], false,
            "Đã ghi nhận xử lý yêu cầu điều chỉnh.", ct);

    [HttpGet("contracts")]
    [Authorize(Roles = "HR,PAYROLL,DIRECTOR")]
    public Task<IActionResult> Contracts([FromQuery] long? employeeId, CancellationToken ct) => Read("contracts", null, employeeId, ct);

    [HttpPost("contracts")]
    [Authorize(Roles = "HR")]
    public Task<IActionResult> CreateContract([FromBody] HrContractRequest request, CancellationToken ct) =>
        Write("PAYROLL_APP.PKG_HR_PORTAL.create_contract", [Number("p_employee", request.EmployeeId), Text("p_no", request.ContractNo),
            Day("p_from", request.ValidFrom), Day("p_to", request.ValidTo), Number("p_salary", request.MonthlySalary),
            Number("p_insurance", request.InsuranceBase), Text("p_enabled", request.InsuranceEnabled ? "Y" : "N"), Number("p_calendar", request.CalendarId)], true,
            "Đã tạo hợp đồng chờ giám đốc phê duyệt.", ct);

    [HttpPost("contracts/{id:long}/decision")]
    [Authorize(Roles = "DIRECTOR")]
    public Task<IActionResult> DecideContract(long id, [FromBody] HrDecisionRequest request, CancellationToken ct) =>
        Write("PAYROLL_APP.PKG_HR_PORTAL.decide_contract", [Number("p_contract", ValidId(id)), Text("p_decision", request.Decision), Text("p_reason", request.Reason)], false,
            "Đã xử lý phê duyệt hợp đồng.", ct);

    [HttpGet("employees/{id:long}")]
    [Authorize(Roles = "HR")]
    public Task<IActionResult> Employee(long id, CancellationToken ct) => Execute(async actor =>
    {
        var rows = await repository.ReadAsync(actor, "profile", null, ValidId(id), ct);
        return rows.Count == 0 ? NotFound(new { message = "Không tìm thấy nhân viên." }) : Ok(rows[0]);
    });

    [HttpPut("employees/{id:long}")]
    [Authorize(Roles = "HR")]
    public Task<IActionResult> UpdateEmployee(long id, [FromBody] HrEmployeeUpdateRequest request, CancellationToken ct) =>
        Write("PAYROLL_APP.PKG_HR_PORTAL.update_employee", [Number("p_employee", ValidId(id)), Text("p_name", request.FullName), Text("p_email", request.Email),
            Day("p_birth", request.BirthDate), Text("p_status", request.Status), Day("p_termination", request.TerminationDate), Number("p_version", request.RowVersion)], false,
            "Đã cập nhật hồ sơ nhân viên.", ct);

    [HttpPost("employees/{id:long}/transfer")]
    [Authorize(Roles = "HR")]
    public Task<IActionResult> TransferEmployee(long id, [FromBody] HrTransferRequest request, CancellationToken ct) =>
        Write("PAYROLL_APP.PKG_HR_PORTAL.transfer_employee", [Number("p_employee", ValidId(id)), Number("p_department", request.DepartmentId),
            Number("p_position", request.PositionId), Day("p_from", request.ValidFrom), Text("p_reason", request.Reason)], true,
            "Đã tạo phiên bản phân công mới và giữ lịch sử cũ.", ct);

    [HttpGet("shifts")]
    [Authorize(Roles = "HR")]
    public Task<IActionResult> Shifts([FromQuery] long? periodId, [FromQuery] long? employeeId, CancellationToken ct) => Read("shiftsScheduled", periodId, employeeId, ct);

    [HttpPost("shifts")]
    [Authorize(Roles = "HR")]
    public Task<IActionResult> SaveShift([FromBody] HrShiftRequest request, CancellationToken ct) =>
        Write("PAYROLL_APP.PKG_HR_PORTAL.save_shift", [Number("p_employee", request.EmployeeId), Day("p_date", request.WorkDate), Number("p_shift", request.ShiftId)], true,
            "Đã phân công ca làm việc.", ct);

    [HttpGet("attendance/raw")]
    [Authorize(Roles = "HR")]
    public Task<IActionResult> RawAttendance(CancellationToken ct) => Read("raw", null, null, ct);

    [HttpPost("attendance/import")]
    [Authorize(Roles = "HR")]
    [RequestSizeLimit(2 * 1024 * 1024 + 65536)]
    public Task<IActionResult> ImportAttendance([FromForm] IFormFile file, CancellationToken ct) => Execute(async actor =>
    {
        return Ok(await repository.ImportAttendanceAsync(actor, file, ct));
    });

    private Task<IActionResult> Read(string resource, long? periodId, long? employeeId, CancellationToken ct) => Execute(async actor =>
        Ok(await repository.ReadAsync(actor, resource, periodId, employeeId, ct)));

    private Task<IActionResult> Write(string procedure, OracleParameter[] parameters, bool returnsId, string message, CancellationToken ct) => Execute(async actor =>
    {
        var id = await repository.WriteAsync(actor, procedure, parameters, returnsId, ct);
        return Ok(new { id, message });
    });

    private static long ValidId(long id) => id > 0 ? id : 0;

    private async Task<IActionResult> Execute(Func<long, Task<IActionResult>> action)
    {
        var identity = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (!long.TryParse(identity, NumberStyles.None, CultureInfo.InvariantCulture, out var actor) || actor <= 0)
            return Unauthorized();
        try { return await action(actor); }
        catch (System.Text.DecoderFallbackException) { return BadRequest(new { message = "Tệp CSV cần được lưu theo mã hóa UTF-8." }); }
        catch (HrInputException ex) { return BadRequest(new { message = ex.Message }); }
        catch (OracleException ex) when (ex.Number is 20002 or 20403) { return Forbid(); }
        catch (OracleException ex) when (ex.Number is 1403 or 20404) { return NotFound(new { message = "Không tìm thấy hồ sơ, hợp đồng, kỳ lương hoặc dữ liệu được chọn." }); }
        catch (OracleException ex) when (ex.Number == 54)
        {
            return StatusCode(StatusCodes.Status503ServiceUnavailable, new { message = "Dữ liệu đang được xử lý bởi thao tác khác. Vui lòng thử lại sau." });
        }
        catch (OracleException ex) when (ex.Number is 1 or 20409 or 20410 or 20003 or 20006 or 20112 or 20115 or 20118 or 20124 or 20130)
        {
            return Conflict(new { message = ConflictMessage(ex.Number) });
        }
        catch (OracleException ex) when (ex.Number is >= 20000 and <= 20499 || ex.Number is 2290 or 2291 or 12899 or 1438)
        {
            return BadRequest(new { message = BusinessMessage(ex.Number) });
        }
    }

    private static string ConflictMessage(int code) => code switch
    {
        1 => "Dữ liệu đã tồn tại hoặc mã hồ sơ bị trùng. Hãy tải lại danh sách trước khi thử lại.",
        20003 or 20006 or 20112 => "Kỳ công/lương liên quan đã khóa, đang tính hoặc đã duyệt. Cần thực hiện đúng luồng mở lại công trước khi sửa.",
        20115 or 20124 => "Dữ liệu đã được phê duyệt và cần giữ lịch sử. Hãy tạo phiên bản mới.",
        20118 => "Khoảng hiệu lực bị chồng với một phiên bản đã có. Kiểm tra ngày bắt đầu/kết thúc.",
        20130 => "Ca làm việc bị chồng với ca khác của nhân viên.",
        20410 => "Khoảng nghỉ trùng với đơn nghỉ phép đang chờ duyệt hoặc đã duyệt.",
        _ => "Trạng thái dữ liệu đã thay đổi hoặc thiếu điều kiện xử lý. Tải lại hồ sơ; kiểm tra hợp đồng đã duyệt, lịch tháng, phiên bản và người phê duyệt khác người tạo."
    };

    private static string BusinessMessage(int code) => code switch
    {
        20010 => "Công hoặc kỳ lương đã khóa.",
        20011 => "Ngày công phải nằm trong kỳ lương được chọn.",
        20012 => "Nhân viên chưa vào làm hoặc đã nghỉ việc tại ngày được chọn.",
        20013 => "Tổng phút công, phép và lễ vượt số phút chuẩn của lịch làm việc.",
        20014 => "Kỳ lương không ở trạng thái cho phép chốt công.",
        20015 => "Chỉ chốt công sau khi tháng đã kết thúc.",
        20016 => "Đang có phiên bản lương tính/duyệt, chưa thể chốt lại công.",
        20017 => "Còn ngày công có lỗi cần xử lý.",
        20018 => "Còn đơn nghỉ phép chờ duyệt.",
        20019 => "Còn đơn tăng ca chưa duyệt hoặc chưa xác nhận thực làm.",
        20020 => "Còn dữ liệu đầu vào (hợp đồng, phụ cấp, người phụ thuộc hoặc khoản cộng/trừ) chưa duyệt.",
        20021 => "Thiếu công của nhân viên: cần xác nhận từng ngày có quan hệ lao động, kể cả ngày nghỉ có 0 phút.",
        20022 => "Cần nhập lý do mở lại công.",
        20023 => "Không thể mở lại kỳ này: kiểm tra trạng thái khóa/đóng và phiên bản lương đang xử lý.",
        20081 or 20088 or 20091 => "Đơn cần đúng trạng thái và người duyệt/xác nhận phải khác người tạo đơn. Kiểm tra số phút và khoảng thời gian.",
        20082 => "Cần nhập lý do từ chối.",
        20083 => "Khoảng nghỉ phép chồng với đơn đã duyệt.",
        20084 => "Đơn nghỉ phép chưa có phân bổ phút theo ngày.",
        20085 or 20086 => "Phút phép phải nằm trong khoảng đơn và không vượt lịch làm việc.",
        20087 => "Không đủ số phút phép. HR cần kiểm tra/cấp số dư phép hợp lệ.",
        20089 => "Tăng ca chồng với đơn tăng ca đã duyệt.",
        20090 => "Tăng ca chồng với ca làm việc chính đã phân công.",
        20400 => "Thông tin hoặc khoảng ngày không hợp lệ. Kiểm tra ngày hiệu lực, ngày vào/nghỉ làm, trạng thái, số tiền và các danh mục đã chọn.",
        2290 => "Dữ liệu chưa đáp ứng ràng buộc nghiệp vụ. Kiểm tra thời gian, trạng thái và người phê duyệt.",
        2291 => "Danh mục hoặc hồ sơ tham chiếu không còn tồn tại. Hãy tải lại danh sách.",
        12899 or 1438 => "Dữ liệu nhập quá dài hoặc số tiền vượt giới hạn lưu trữ.",
        _ => "Dữ liệu chưa đủ điều kiện xử lý. Kiểm tra lịch làm việc, hợp đồng có hiệu lực, đơn đã duyệt và trạng thái kỳ công/lương."
    };
}
