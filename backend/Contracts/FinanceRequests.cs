using System.ComponentModel.DataAnnotations;

namespace Payroll.Api.Contracts;

public sealed class CreatePeriodRequest
{
    [Required(ErrorMessage = "Vui lòng chọn tháng lương.")]
    public DateOnly? PeriodStart { get; set; }
}

public class FinanceKeyRequest
{
    [Required, StringLength(100, MinimumLength = 1)]
    public string RequestKey { get; set; } = string.Empty;
}

public sealed class CalculatePayrollRequest : FinanceKeyRequest
{
    [Range(typeof(long), "1", "9223372036854775807")]
    public long PeriodId { get; set; }
}

public sealed class CreatePaymentRequest : FinanceKeyRequest
{
    [Range(typeof(long), "1", "9223372036854775807")]
    public long RunId { get; set; }
}

public sealed class RejectPayrollRequest
{
    [Required(ErrorMessage = "Vui lòng nhập lý do từ chối."), StringLength(1000)]
    public string Reason { get; set; } = string.Empty;
}

public sealed class ImportReconciliationRequest
{
    [Required, StringLength(255)]
    public string FileName { get; set; } = "bank-result.csv";

    [Required, StringLength(2_000_000)]
    public string Content { get; set; } = string.Empty;
}

public sealed class FinancePortalException(int statusCode, string message) : Exception(message)
{
    public int StatusCode { get; } = statusCode;
}

public sealed record FinanceDownload(byte[] Content, string FileName, string ContentType = "text/csv; charset=utf-8");
