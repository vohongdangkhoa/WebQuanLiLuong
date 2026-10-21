using System.ComponentModel.DataAnnotations;

namespace Payroll.Api.Contracts;

public class LoginRequest
{
    [Required(ErrorMessage = "Vui lòng nhập tên đăng nhập.")]
    [StringLength(50, ErrorMessage = "Tên đăng nhập tối đa 50 ký tự.")]
    public string Username { get; set; } = string.Empty;

    [Required(ErrorMessage = "Vui lòng nhập mật khẩu.")]
    [StringLength(50, ErrorMessage = "Mật khẩu tối đa 50 ký tự.")]
    public string Password { get; set; } = string.Empty;

}