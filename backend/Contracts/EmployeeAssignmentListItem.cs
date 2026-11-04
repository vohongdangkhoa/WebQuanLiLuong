namespace Payroll.Api.Contracts;

public class EmployeeAssignmentListItem
{
    public long AssignmentId { get; set; }

    public string EmployeeCode { get; set; } = string.Empty;

    public string DepartmentName { get; set; } = string.Empty;

    public string PositionName { get; set; } = string.Empty;

    public DateOnly ValidFrom { get; set; }

    public DateOnly? ValidTo { get; set; }
}

/* AssignmentId: ID của lần phân công.
ValidFrom: ngày bắt đầu áp dụng.
ValidTo: ngày đầu tiên phân công không còn áp dụng. Dấu ? cho phép nhận null, nghĩa là chưa giới hạn ngày kết thúc. */