using System.ComponentModel.DataAnnotations;

namespace Payroll.Api.Contracts;

public sealed class SaveBankAccountRequest
{
    [Range(1, long.MaxValue)] public long EmployeeId { get; set; }
    [Required, StringLength(30, MinimumLength=2), RegularExpression("^[A-Za-z0-9_-]+$")]
    public string BankCode { get; set; } = "";
    [Required, StringLength(150)] public string AccountHolder { get; set; } = "";
    [Required, StringLength(34, MinimumLength=6), RegularExpression("^[A-Za-z0-9]+$")]
    public string AccountNumber { get; set; } = "";
    [Required] public DateOnly? ValidFrom { get; set; }
}
public sealed class BankDecisionRequest
{
    [Required, RegularExpression("^(VERIFY|REJECT)$")] public string Decision { get; set; } = "";
}
public sealed class ChangePasswordRequest
{
    [Required, StringLength(50)] public string CurrentPassword { get; set; } = "";
    [Required, StringLength(50, MinimumLength=8)] public string NewPassword { get; set; } = "";
}
