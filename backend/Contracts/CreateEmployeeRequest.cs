using System.ComponentModel.DataAnnotations;

namespace Payroll.Api.Contracts;

public class CreateEmployeeRequest
{
    [Required(ErrorMessage = "Vui lòng nhập mã nhân viên.")]
    [StringLength(30, ErrorMessage = "Mã nhân viên tối đa 30 ký tự.")]
    public string EmployeeCode { get; set; } = string.Empty;

    [Required(ErrorMessage = "Vui lòng nhập họ tên.")]
    [StringLength(150, ErrorMessage = "Họ tên tối đa 150 ký tự.")]
    public string FullName { get; set; } = string.Empty;

    [Required(ErrorMessage = "Vui lòng chọn ngày vào làm.")]
    public DateOnly? HireDate { get; set; }
}
/* EmployeeCode, FullName, HireDate: mã nhân viên, họ tên và ngày vào làm.
[Required]: thông tin bắt buộc.
[StringLength(...)]: giới hạn độ dài, khớp với bảng Oracle.
DateOnly: kiểu dữ liệu chỉ chứa ngày, không chứa giờ.
Dấu ? cho phép nhận null khi người dùng chưa điền ngày; [Required] sẽ phát hiện và báo thiếu.
string.Empty: giá trị ban đầu là chuỗi rỗng "". */