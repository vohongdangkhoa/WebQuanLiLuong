using System.ComponentModel.DataAnnotations;

namespace Payroll.Api.Contracts;

public sealed class CreateEmployeeAccountRequest
{
    [Required, RegularExpression(@"^0[0-9]{9}$", ErrorMessage = "Nhập số điện thoại gồm 10 chữ số, bắt đầu bằng 0.")]
    public string PhoneNumber { get; set; } = "";

    [Required(ErrorMessage = "Vui lòng bổ sung ngày sinh.")]
    public DateOnly? BirthDate { get; set; }

    [Range(1, long.MaxValue, ErrorMessage = "Vui lòng tải lại hồ sơ nhân viên.")]
    public long RowVersion { get; set; }
}

public sealed record EmployeeAccountContext(
    long EmployeeId, string EmployeeCode, string FullName, DateOnly? BirthDate,
    DateOnly HireDate, string? PhoneNumber, string Status, DateOnly? TerminationDate,
    long RowVersion, long? UserId, string? Username, bool? AccountActive);

public sealed record CreatedEmployeeAccount(long UserId, string Username, string InitialPassword);
