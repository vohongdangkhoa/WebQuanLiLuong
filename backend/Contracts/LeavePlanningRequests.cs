using System.ComponentModel.DataAnnotations;

namespace Payroll.Api.Contracts;

public class LeavePlanRequest : IValidatableObject
{
    [Range(typeof(long), "1", "9223372036854775807")]
    public long EmployeeId { get; set; }
    [Required] public DateOnly? StartDate { get; set; }
    [Required] public DateOnly? LastDate { get; set; }
    [Required, RegularExpression("^(FULL|HALF|HOURS)$")]
    public string Duration { get; set; } = "FULL";
    [Range(typeof(decimal), "0.25", "24")]
    public decimal? HoursPerDay { get; set; }

    public IEnumerable<ValidationResult> Validate(ValidationContext context)
    {
        if (StartDate is not null && LastDate is not null &&
            (LastDate < StartDate || LastDate.Value.DayNumber - StartDate.Value.DayNumber > 365 || LastDate == DateOnly.MaxValue))
            yield return new ValidationResult("Chọn khoảng nghỉ từ 1 đến 366 ngày, tính cả ngày kết thúc.", [nameof(LastDate)]);
        if (Duration == "HOURS" && (HoursPerDay is null || HoursPerDay * 60 != decimal.Truncate(HoursPerDay.Value * 60)))
            yield return new ValidationResult("Nhập số giờ nghỉ hợp lệ, ví dụ 1,5 giờ hoặc 2 giờ.", [nameof(HoursPerDay)]);
    }
}

public sealed class ScheduledLeaveRequest : LeavePlanRequest
{
    [Range(typeof(long), "1", "9223372036854775807")]
    public long LeaveTypeId { get; set; }
    [Required, StringLength(1000, MinimumLength = 3)] public string Reason { get; set; } = "";
    [Required, RegularExpression("^[A-F0-9]{64}$")] public string ScheduleToken { get; set; } = "";
}

public sealed record LeavePlanDay(DateOnly WorkDate, long? ContractId, long? CalendarId, string? CalendarName,
    string? DayType, int? StandardMinutes, int? LeaveMinutes, string? IssueCode);

public sealed record LeavePlanResponse(IReadOnlyList<LeavePlanDay> Days, int WorkingDays, int SkippedDays,
    int TotalMinutes, IReadOnlyList<string> Issues, string ScheduleToken, bool CanSubmit);
