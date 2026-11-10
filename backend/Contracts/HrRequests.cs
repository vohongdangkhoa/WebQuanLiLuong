using System.ComponentModel.DataAnnotations;

namespace Payroll.Api.Contracts;

public sealed class OrganizationCatalogRequest
{
    [Range(typeof(long), "1", "9223372036854775807")]
    public long? Id { get; set; }
    [Required, StringLength(30)]
    public string Code { get; set; } = string.Empty;
    [Required, StringLength(150)]
    public string Name { get; set; } = string.Empty;
    [Required, RegularExpression("^[YN]$")]
    public string IsActive { get; set; } = string.Empty;
}

public class HrPeriodRequest
{
    [Range(typeof(long), "1", "9223372036854775807")]
    public long PeriodId { get; set; }
}

public class HrReopenRequest : HrPeriodRequest
{
    [Required, StringLength(1000, MinimumLength = 3)]
    public string Reason { get; set; } = string.Empty;
}

public class HrAttendanceRequest : HrPeriodRequest
{
    [Range(typeof(long), "1", "9223372036854775807")]
    public long EmployeeId { get; set; }
    [Required]
    public DateOnly? WorkDate { get; set; }
    [Range(0, 1440)]
    public int WorkedMinutes { get; set; }
    [Range(0, 1440)]
    public int LeaveMinutes { get; set; }
    [Range(0, 1440)]
    public int HolidayMinutes { get; set; }
    public bool Certified { get; set; }
}

public class HrCalendarRequest
{
    [Range(typeof(long), "1", "9223372036854775807")]
    public long CalendarId { get; set; }
    [Required]
    public DateOnly? MonthDate { get; set; }
}

public class HrLeaveCreditRequest
{
    [Range(typeof(long), "1", "9223372036854775807")]
    public long EmployeeId { get; set; }
    [Range(typeof(long), "1", "9223372036854775807")]
    public long LeaveTypeId { get; set; }
    [Required]
    public DateOnly? EffectiveDate { get; set; }
    [Range(1, 525600)]
    public int Minutes { get; set; }
    [Required, StringLength(1000, MinimumLength = 3)]
    public string Reason { get; set; } = string.Empty;
    [Required, StringLength(70)]
    public string RequestKey { get; set; } = string.Empty;
}

public class HrCalendarDayRequest
{
    [Range(typeof(long), "1", "9223372036854775807")]
    public long CalendarId { get; set; }
    [Required]
    public DateOnly? WorkDate { get; set; }
    [Required, RegularExpression("^(WORKDAY|RESTDAY|HOLIDAY)$")]
    public string DayType { get; set; } = "WORKDAY";
    [Range(0, 1440)]
    public int StandardMinutes { get; set; }
}

public class HrLeaveRequest
{
    [Range(typeof(long), "1", "9223372036854775807")]
    public long EmployeeId { get; set; }
    [Range(typeof(long), "1", "9223372036854775807")]
    public long LeaveTypeId { get; set; }
    [Required]
    public DateOnly? StartDate { get; set; }
    [Required]
    public DateOnly? EndDate { get; set; }
    [Range(1, 1440)]
    public int MinutesPerDay { get; set; } = 480;
    [Required, StringLength(1000, MinimumLength = 3)]
    public string Reason { get; set; } = string.Empty;
}

public class HrOvertimeRequest
{
    [Range(typeof(long), "1", "9223372036854775807")]
    public long EmployeeId { get; set; }
    [Required]
    public DateTime? StartsAt { get; set; }
    [Required]
    public DateTime? EndsAt { get; set; }
    [Required, StringLength(1000, MinimumLength = 3)]
    public string Reason { get; set; } = string.Empty;
}

public class HrOvertimeApprovalRequest
{
    [Range(1, 1440)]
    public int Minutes { get; set; }
}

public class HrOvertimeConfirmationRequest
{
    [Required]
    public DateTime? ActualStart { get; set; }
    [Required]
    public DateTime? ActualEnd { get; set; }
}

public class HrDecisionRequest
{
    [Required, RegularExpression("^(APPROVE|REJECT)$")]
    public string Decision { get; set; } = string.Empty;
    [StringLength(1000)]
    public string? Reason { get; set; }
}

public class HrReasonRequest
{
    [Required, StringLength(1000, MinimumLength = 3)]
    public string Reason { get; set; } = string.Empty;
}

public class HrCorrectionRequest : HrReasonRequest
{
    [Range(typeof(long), "1", "9223372036854775807")]
    public long PeriodId { get; set; }
    [Range(typeof(long), "1", "9223372036854775807")]
    public long? EmployeeId { get; set; }
    [Required, RegularExpression("^(TIMESHEET|CONTRACT|OTHER)$")]
    public string SourceType { get; set; } = "TIMESHEET";
    [Range(typeof(long), "1", "9223372036854775807")]
    public long? SourceId { get; set; }
}

public class HrContractRequest
{
    [Range(typeof(long), "1", "9223372036854775807")]
    public long EmployeeId { get; set; }
    [Required, StringLength(60)]
    public string ContractNo { get; set; } = string.Empty;
    [Required]
    public DateOnly? ValidFrom { get; set; }
    public DateOnly? ValidTo { get; set; }
    [Range(typeof(decimal), "0.01", "9999999999999999.99", ParseLimitsInInvariantCulture = true)]
    public decimal MonthlySalary { get; set; }
    [Range(typeof(decimal), "0", "9999999999999999.99", ParseLimitsInInvariantCulture = true)]
    public decimal InsuranceBase { get; set; }
    public bool InsuranceEnabled { get; set; } = true;
    [Range(typeof(long), "1", "9223372036854775807")]
    public long CalendarId { get; set; }
}

public class HrEmployeeUpdateRequest
{
    [Required, StringLength(150)]
    public string FullName { get; set; } = string.Empty;
    [EmailAddress, StringLength(200)]
    public string? Email { get; set; }
    public DateOnly? BirthDate { get; set; }
    [Required, RegularExpression("^(ACTIVE|INACTIVE|TERMINATED)$")]
    public string Status { get; set; } = "ACTIVE";
    public DateOnly? TerminationDate { get; set; }
    [Range(typeof(long), "1", "9999999999")]
    public long RowVersion { get; set; }
}

public class HrTransferRequest : HrReasonRequest
{
    [Range(typeof(long), "1", "9223372036854775807")]
    public long DepartmentId { get; set; }
    [Range(typeof(long), "1", "9223372036854775807")]
    public long PositionId { get; set; }
    [Required]
    public DateOnly? ValidFrom { get; set; }
}

public class HrShiftRequest
{
    [Range(typeof(long), "1", "9223372036854775807")]
    public long EmployeeId { get; set; }
    [Range(typeof(long), "1", "9223372036854775807")]
    public long ShiftId { get; set; }
    [Required]
    public DateOnly? WorkDate { get; set; }
}
