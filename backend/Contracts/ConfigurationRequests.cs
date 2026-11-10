using System.ComponentModel.DataAnnotations;

namespace Payroll.Api.Contracts;

public class ConfigurationInterval : IValidatableObject
{
    [Required] public DateOnly? ValidFrom { get; init; }
    public DateOnly? ValidTo { get; init; }
    public virtual IEnumerable<ValidationResult> Validate(ValidationContext context)
    {
        if (ValidFrom.HasValue && ValidTo.HasValue && ValidTo <= ValidFrom)
            yield return new ValidationResult("Ngày kết thúc phải sau ngày bắt đầu.", [nameof(ValidTo)]);
    }
}

public sealed class ConfigurationTaxBand
{
    [Required, Range(typeof(decimal), "0", "999999999999999")] public decimal? LowerBound { get; init; }
    [Range(typeof(decimal), "0", "999999999999999")] public decimal? UpperBound { get; init; }
    [Required, Range(typeof(decimal), "0", "1")] public decimal? Rate { get; init; }
}

public sealed class CreatePolicyRequest : ConfigurationInterval
{
    [Required, StringLength(40)] public string PolicyCode { get; init; } = "";
    [Required, Range(typeof(decimal), "0", "1")] public decimal? EmployeeInsuranceRate { get; init; }
    [Required, Range(typeof(decimal), "0", "1")] public decimal? EmployerInsuranceRate { get; init; }
    [Required, Range(typeof(decimal), "0.01", "9999999999999")] public decimal? InsuranceCap { get; init; }
    [Required, Range(typeof(decimal), "0", "9999999999999")] public decimal? PersonalRelief { get; init; }
    [Required, Range(typeof(decimal), "0", "9999999999999")] public decimal? DependentRelief { get; init; }
    [Required, Range(typeof(decimal), "1", "99")] public decimal? OtWorkdayFactor { get; init; }
    [Required, Range(typeof(decimal), "1", "99")] public decimal? OtRestdayFactor { get; init; }
    [Required, Range(typeof(decimal), "1", "99")] public decimal? OtHolidayFactor { get; init; }
    [Required, Range(typeof(decimal), "0", "99")] public decimal? NightExtraFactor { get; init; }
    [Required, Range(typeof(decimal), "0", "1")] public decimal? OtTaxableFraction { get; init; }
    [Required, Range(0, 2)] public int? RoundScale { get; init; }
    [Required, StringLength(1000)] public string SourceNote { get; init; } = "";
    [Required, MinLength(1), MaxLength(50)] public List<ConfigurationTaxBand> Brackets { get; init; } = [];

    public override IEnumerable<ValidationResult> Validate(ValidationContext context)
    {
        foreach (var error in base.Validate(context)) yield return error;
        if (Brackets is null || Brackets.Count == 0)
        {
            yield return new ValidationResult("Cần ít nhất một bậc thuế.", [nameof(Brackets)]);
            yield break;
        }
        decimal next = 0;
        for (var i = 0; i < Brackets.Count; i++)
        {
            var band = Brackets[i];
            if (band is null || band.LowerBound != next ||
                (i == Brackets.Count - 1 ? band.UpperBound.HasValue : !band.UpperBound.HasValue || band.UpperBound <= band.LowerBound))
            {
                yield return new ValidationResult("Bậc thuế phải liên tục từ 0, tăng dần và bậc cuối không có giới hạn trên.", [nameof(Brackets)]);
                yield break;
            }
            next = band.UpperBound ?? 0;
        }
    }
}

public sealed class CreateAllowanceRequest : ConfigurationInterval
{
    [Range(typeof(long), "1", "9223372036854775807")] public long EmployeeId { get; init; }
    [Range(typeof(long), "1", "9223372036854775807")] public long ComponentId { get; init; }
    [Required, Range(typeof(decimal), "0", "9999999999999")] public decimal? Amount { get; init; }
    [Required, RegularExpression("^(FULL_MONTH|PAID_MINUTES|CALENDAR_DAYS)$")] public string AllocationMethod { get; init; } = "";
}

public sealed class CreateConfigurationEntryRequest
{
    [Range(typeof(long), "1", "9223372036854775807")] public long EmployeeId { get; init; }
    [Range(typeof(long), "1", "9223372036854775807")] public long PeriodId { get; init; }
    [Range(typeof(long), "1", "9223372036854775807")] public long ComponentId { get; init; }
    [Required, Range(typeof(decimal), "0.01", "9999999999999")] public decimal? Amount { get; init; }
    [Range(typeof(long), "1", "9223372036854775807")] public long? DeductionAccountId { get; init; }
    [Required, StringLength(1000)] public string Reason { get; init; } = "";
}

public sealed class CreateDeductionAccountRequest
{
    [Range(typeof(long), "1", "9223372036854775807")] public long EmployeeId { get; init; }
    [Required, Range(typeof(decimal), "0.01", "9999999999999")] public decimal? PrincipalAmount { get; init; }
    [Required, Range(typeof(decimal), "0.01", "9999999999999")] public decimal? MonthlyLimit { get; init; }
    [Required, StringLength(500)] public string Description { get; init; } = "";
}

public sealed class CreateDependentRequest : ConfigurationInterval
{
    [Range(typeof(long), "1", "9223372036854775807")] public long EmployeeId { get; init; }
    [Required, StringLength(128)] public string Identity { get; init; } = "";
    [Required, StringLength(150)] public string FullName { get; init; } = "";
    public DateOnly? BirthDate { get; init; }
    [Range(typeof(long), "1", "9223372036854775807")] public long DocumentId { get; init; }
}

public sealed class ConfigurationDecisionRequest : IValidatableObject
{
    [Required, RegularExpression("^(APPROVE|REJECT)$")] public string Decision { get; init; } = "";
    [StringLength(1000)] public string? Reason { get; init; }
    public IEnumerable<ValidationResult> Validate(ValidationContext context)
    {
        if (Decision == "REJECT" && string.IsNullOrWhiteSpace(Reason))
            yield return new ValidationResult("Vui lòng nhập lý do từ chối.", [nameof(Reason)]);
    }
}

public sealed class EndPolicyRequest
{
    [Required] public DateOnly? ValidTo { get; init; }
    [Required, StringLength(1000)] public string Reason { get; init; } = "";
}
