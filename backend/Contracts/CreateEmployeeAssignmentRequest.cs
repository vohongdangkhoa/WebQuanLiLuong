using System.ComponentModel.DataAnnotations;

namespace Payroll.Api.Contracts;

public class CreateEmployeeAssignmentRequest
{
    [Range(
        typeof(long), "1", "9223372036854775807",
        ErrorMessage = "Vui lòng chọn phòng ban hợp lệ.")]
    public long DepartmentId { get; set; }

    [Range(
        typeof(long), "1", "9223372036854775807",
        ErrorMessage = "Vui lòng chọn chức danh hợp lệ.")]
    public long PositionId { get; set; }

    [Required(ErrorMessage = "Vui lòng chọn ngày bắt đầu phân công.")]
    public DateOnly? ValidFrom { get; set; }
}