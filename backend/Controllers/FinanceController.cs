using System.Globalization;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Oracle.ManagedDataAccess.Client;
using Payroll.Api.Contracts;
using Payroll.Api.Data;

namespace Payroll.Api.Controllers;

[ApiController]
[Route("api/finance")]
[Authorize]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class FinanceController(OracleFinanceRepository repository, ILogger<FinanceController> logger) : ControllerBase
{
    private long Actor()
    {
        if (!long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), NumberStyles.None, CultureInfo.InvariantCulture, out var actor) || actor <= 0)
            throw new FinancePortalException(401, "Phiên đăng nhập không hợp lệ.");
        return actor;
    }

    private static long Positive(long id)
    {
        if (id <= 0) throw new FinancePortalException(400, "Mã định danh phải là số nguyên dương.");
        return id;
    }

    private static long? Optional(long? id) => id.HasValue ? Positive(id.Value) : null;

    private async Task<IActionResult> Guard(Func<Task<IActionResult>> action)
    {
        try { return await action(); }
        catch (FinancePortalException ex) { return StatusCode(ex.StatusCode, new { message = ex.Message }); }
        catch (OracleException ex)
        {
            var error = FinanceErrors.Describe(ex.Number);
            logger.LogWarning("Finance Oracle operation failed with code {OracleCode}, trace {TraceId}", ex.Number, HttpContext.TraceIdentifier);
            return StatusCode(error.Status, new { message = error.Message });
        }
        catch (OverflowException)
        {
            return StatusCode(500, new { message = "Giá trị Oracle vượt giới hạn cho phép; giao dịch chưa được xác nhận." });
        }
    }

    [HttpGet("periods")]
    [Authorize(Roles = "HR,PAYROLL,DIRECTOR")]
    public Task<IActionResult> Periods(CancellationToken ct) => Guard(async () =>
        Ok(await repository.ReadAsync("PAYROLL_APP.PKG_FINANCE_PORTAL.list_periods", Actor(), ct)));

    [HttpPost("periods")]
    [Authorize(Roles = "PAYROLL")]
    public Task<IActionResult> CreatePeriod(CreatePeriodRequest request, CancellationToken ct) => Guard(async () =>
    {
        if (request.PeriodStart is not DateOnly start || start.Day != 1)
            return BadRequest(new { message = "Vui lòng chọn ngày đầu tiên của tháng lương." });
        var periodId = await repository.CreatePeriodAsync(Actor(), start, ct);
        return StatusCode(201, new { periodId, message = "Đã tạo kỳ lương." });
    });

    [HttpGet("runs")]
    [Authorize(Roles = "PAYROLL,DIRECTOR")]
    public Task<IActionResult> Runs([FromQuery] long? periodId, CancellationToken ct) => Guard(async () =>
        Ok(await repository.ReadAsync("PAYROLL_APP.PKG_FINANCE_PORTAL.list_runs", Actor(), ct, OracleFinanceRepository.Id("p_period", Optional(periodId)))));

    [HttpPost("runs")]
    [Authorize(Roles = "PAYROLL")]
    public Task<IActionResult> Calculate(CalculatePayrollRequest request, CancellationToken ct) => Guard(async () =>
    {
        var runId = await repository.CalculateAsync(Actor(), request.PeriodId, request.RequestKey, ct);
        return StatusCode(201, new { runId, message = "Đã xử lý tính lương. Kiểm tra trạng thái và danh sách lỗi của phiên bản vừa tạo." });
    });

    [HttpPost("runs/{runId:long}/calculate")]
    [Authorize(Roles = "PAYROLL")]
    public Task<IActionResult> Recalculate(long runId, FinanceKeyRequest request, CancellationToken ct) => Guard(async () =>
    {
        var newRunId = await repository.RecalculateAsync(Actor(), Positive(runId), request.RequestKey, ct);
        return StatusCode(201, new { runId = newRunId, message = "Đã xử lý phiên bản lương cho cùng kỳ; kiểm tra kết quả và lỗi." });
    });

    [HttpGet("runs/{runId:long}/results")]
    [Authorize(Roles = "PAYROLL,DIRECTOR")]
    public Task<IActionResult> Results(long runId, CancellationToken ct) => Guard(async () =>
        Ok(await repository.ReadAsync("PAYROLL_APP.PKG_FINANCE_PORTAL.list_results", Actor(), ct, OracleFinanceRepository.Id("p_run", Positive(runId)))));

    [HttpGet("runs/{runId:long}/errors")]
    [Authorize(Roles = "PAYROLL,DIRECTOR")]
    public Task<IActionResult> Errors(long runId, CancellationToken ct) => Guard(async () =>
        Ok(await repository.ReadAsync("PAYROLL_APP.PKG_FINANCE_PORTAL.list_errors", Actor(), ct, OracleFinanceRepository.Id("p_run", Positive(runId)))));

    [HttpGet("results/{resultId:long}/items")]
    [Authorize(Roles = "PAYROLL,DIRECTOR")]
    public Task<IActionResult> Items(long resultId, CancellationToken ct) => Guard(async () =>
        Ok(await repository.ReadAsync("PAYROLL_APP.PKG_FINANCE_PORTAL.list_items", Actor(), ct, OracleFinanceRepository.Id("p_result", Positive(resultId)))));

    [HttpPost("runs/{runId:long}/submit")]
    [Authorize(Roles = "PAYROLL")]
    public Task<IActionResult> Submit(long runId, CancellationToken ct) => Guard(async () =>
    {
        await repository.WriteAsync("PAYROLL_APP.PKG_PAYROLL_CORE.submit_run", Actor(), ct, OracleFinanceRepository.Id("p_run", Positive(runId)));
        return Ok(new { message = "Đã gửi bảng lương chờ giám đốc phê duyệt." });
    });

    [HttpPost("runs/{runId:long}/approve")]
    [Authorize(Roles = "DIRECTOR")]
    public Task<IActionResult> Approve(long runId, CancellationToken ct) => Guard(async () =>
    {
        await repository.DecideAsync(Actor(), Positive(runId), "APPROVE", null, ct);
        return Ok(new { message = "Đã phê duyệt và phát hành phiếu lương." });
    });

    [HttpPost("runs/{runId:long}/withdraw")]
    [Authorize(Roles = "PAYROLL")]
    public Task<IActionResult> Withdraw(long runId, HrReasonRequest request, CancellationToken ct) => Guard(async () =>
    {
        await repository.WithdrawAsync(Actor(), Positive(runId), request.Reason.Trim(), ct);
        return Ok(new { message = "Đã thu hồi phiên bản chờ duyệt. HR có thể mở lại bảng công để điều chỉnh." });
    });

    [HttpPost("runs/{runId:long}/reject")]
    [Authorize(Roles = "DIRECTOR")]
    public Task<IActionResult> Reject(long runId, RejectPayrollRequest request, CancellationToken ct) => Guard(async () =>
    {
        await repository.DecideAsync(Actor(), Positive(runId), "REJECT", request.Reason.Trim(), ct);
        return Ok(new { message = "Đã từ chối bảng lương và lưu lý do." });
    });

    [HttpGet("payments")]
    [Authorize(Roles = "PAYROLL,DIRECTOR")]
    public Task<IActionResult> Payments([FromQuery] long? runId, CancellationToken ct) => Guard(async () =>
        Ok(await repository.ReadAsync("PAYROLL_APP.PKG_FINANCE_PORTAL.list_batches", Actor(), ct, OracleFinanceRepository.Id("p_run", Optional(runId)))));

    [HttpPost("payments")]
    [Authorize(Roles = "PAYROLL")]
    public Task<IActionResult> CreatePayment(CreatePaymentRequest request, CancellationToken ct) => Guard(async () =>
    {
        var batchId = await repository.CreateBatchAsync(Actor(), request.RunId, request.RequestKey, ct);
        return StatusCode(201, new { batchId, message = "Đã lập đợt thanh toán; chưa chuyển tiền." });
    });

    [HttpGet("payments/{batchId:long}/items")]
    [Authorize(Roles = "PAYROLL,DIRECTOR")]
    public Task<IActionResult> PaymentItems(long batchId, CancellationToken ct) => Guard(async () =>
        Ok(await repository.ReadAsync("PAYROLL_APP.PKG_FINANCE_PORTAL.list_payment_items", Actor(), ct, OracleFinanceRepository.Id("p_batch", Positive(batchId)))));

    [HttpPost("payments/{batchId:long}/export")]
    [Authorize(Roles = "PAYROLL")]
    public Task<IActionResult> Export(long batchId, CancellationToken ct) => Guard(async () =>
    {
        var file = await repository.ExportAsync(Actor(), Positive(batchId), ct);
        return File(file.Content, file.ContentType, file.FileName);
    });

    [HttpPost("payments/{batchId:long}/sent")]
    [Authorize(Roles = "PAYROLL")]
    public Task<IActionResult> Sent(long batchId, CancellationToken ct) => Guard(async () =>
    {
        await repository.WriteAsync("PAYROLL_APP.PKG_PAYMENT.mark_sent", Actor(), ct, OracleFinanceRepository.Id("p_batch", Positive(batchId)));
        return Ok(new { message = "Đã ghi nhận xác nhận gửi bên ngoài; giao dịch đang chờ bằng chứng ngân hàng." });
    });

    [HttpGet("payments/{batchId:long}/reconciliation")]
    [Authorize(Roles = "PAYROLL,DIRECTOR")]
    public Task<IActionResult> Reconciliation(long batchId, CancellationToken ct) => Guard(async () =>
        Ok(await repository.ReadAsync("PAYROLL_APP.PKG_FINANCE_PORTAL.list_recon", Actor(), ct, OracleFinanceRepository.Id("p_batch", Positive(batchId)))));

    [HttpPost("payments/{batchId:long}/reconcile")]
    [Authorize(Roles = "PAYROLL")]
    [RequestSizeLimit(3_000_000)]
    public Task<IActionResult> Reconcile(long batchId, ImportReconciliationRequest request, CancellationToken ct) => Guard(async () =>
    {
        var result = await repository.ReconcileAsync(Actor(), Positive(batchId), request, ct);
        return Ok(new { importId = result.ImportId, lineCount = result.LineCount,
            message = "Đã nhập bằng chứng và đối soát. Kiểm tra từng dòng MATCHED/AMOUNT_MISMATCH/CONFLICT trước khi đóng kỳ." });
    });

    [HttpPost("periods/{periodId:long}/close")]
    [Authorize(Roles = "DIRECTOR")]
    public Task<IActionResult> Close(long periodId, CancellationToken ct) => Guard(async () =>
    {
        await repository.WriteAsync("PAYROLL_APP.PKG_PAYMENT.close_period", Actor(), ct, OracleFinanceRepository.Id("p_period", Positive(periodId)));
        return Ok(new { message = "Đã đóng kỳ lương sau khi kiểm tra thanh toán và đối soát." });
    });

    [HttpGet("payslips")]
    [Authorize(Roles = "EMPLOYEE")]
    public Task<IActionResult> Payslips(CancellationToken ct) => Guard(async () =>
        Ok(await repository.ReadAsync("PAYROLL_APP.PKG_PAYROLL_READ.my_payslips", Actor(), ct)));

    [HttpGet("payslips/{resultId:long}/items")]
    [Authorize(Roles = "EMPLOYEE")]
    public Task<IActionResult> PayslipItems(long resultId, CancellationToken ct) => Guard(async () =>
        Ok(await repository.ReadAsync("PAYROLL_APP.PKG_PAYROLL_READ.my_payslip_items", Actor(), ct, OracleFinanceRepository.Id("p_result", Positive(resultId)))));

    [HttpGet("reports")]
    [Authorize(Roles = "PAYROLL,DIRECTOR")]
    public Task<IActionResult> Reports([FromQuery] long? periodId, CancellationToken ct) => Guard(async () =>
        Ok(await repository.ReadAsync("PAYROLL_APP.PKG_FINANCE_PORTAL.reports", Actor(), ct, OracleFinanceRepository.Id("p_period", Optional(periodId)))));

    [HttpGet("reports/export")]
    [Authorize(Roles = "PAYROLL,DIRECTOR")]
    public Task<IActionResult> ExportReports([FromQuery] long? periodId, CancellationToken ct) => Guard(async () =>
    {
        var rows = await repository.ReadAsync("PAYROLL_APP.PKG_FINANCE_PORTAL.reports", Actor(), ct, OracleFinanceRepository.Id("p_period", Optional(periodId)));
        return File(OracleFinanceRepository.Csv(rows), "text/csv; charset=utf-8", "bao-cao-luong.csv");
    });
}
