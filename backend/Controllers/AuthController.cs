using Microsoft.AspNetCore.Antiforgery;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using Payroll.Api.Contracts;
using Payroll.Api.Services;
using System.Globalization;
using System.Security.Claims;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;

namespace Payroll.Api.Controllers;

[ApiController]/*[ApiController]: bật cách xử lý dành cho API, gồm kiểm tra dữ liệu đầu vào.*/
[Route("api/auth")]/*[Route("api/auth")]: các API trong lớp này sẽ có đường dẫn bắt đầu bằng /api/auth*/   /**/
public class AuthController : ControllerBase/*ControllerBase: lớp có sẵn giúp mình trả kết quả cho React.*/
{
    private readonly AuthService _authService;/*_authService: sử dụng phần kiểm tra tài khoản và mật khẩu đã viết.*/
    private readonly IAntiforgery _antiforgery;/*_antiforgery: sử dụng phần cấp mã CSRF.*/

    public AuthController(
        AuthService authService,
        IAntiforgery antiforgery)
    {
        _authService = authService;
        _antiforgery = antiforgery;
    }
    [HttpGet("csrf")]  /*[HttpGet("csrf")]: kết hợp với [Route("api/auth")] ở đầu lớp, tạo đường dẫn GET /api/auth/csrf.*/
[AllowAnonymous]  /*[AllowAnonymous]: cho phép người chưa đăng nhập lấy mã. Mình cần mã này trước khi gửi yêu cầu đăng nhập.*/
public IActionResult GetCsrfToken()  /**/
{
    var tokens = _antiforgery.GetAndStoreTokens(HttpContext);  /*GetAndStoreTokens(...): tạo bộ mã CSRF và gửi cookie CSRF cho trình duyệt khi cần*/

    return Ok(new
    {
        token = tokens.RequestToken  /*Ok(...): trả HTTP 200 cùng dữ liệu JSON chứa trường token để React sử dụng.*/
    });
}
/*phần nhận và kiểm tra thông tin đăng nhập trước, rồi bước kế thêm phần tạo cookie.*/
[HttpPost("login")] /*[HttpPost("login")]: tạo API POST /api/auth/login để React gửi thông tin đăng nhập.*/
[AllowAnonymous] 
public async Task<IActionResult> Login(
    [FromBody] LoginRequest request,
    CancellationToken cancellationToken)/*[FromBody] LoginRequest request: đọc dữ liệu JSON React gửi vào đối tượng LoginRequest. Hai trường vẫn được kiểm tra bắt buộc và tối đa 50 ký tự theo lớp đã viết.*/
{
    var user = await _authService.ValidateCredentialsAsync(/*ValidateCredentialsAsync(...): gọi phần kiểm tra tài khoản và mật khẩu đã làm.*/
        request.Username,
        request.Password,
        cancellationToken);

    if (user is null)/*user is null: thông tin không hợp lệ → trả HTTP 401.*/
    {
        return Unauthorized(new
        {
            message = "Tên đăng nhập hoặc mật khẩu không đúng."
        });
    }
    /* NameIdentifier: mã tài khoản.
Name: tên đăng nhập.
"security_version": phiên bản bảo mật để đối chiếu với Oracle.
Role: mỗi quyền của tài khoản được thêm thành một claim. */
    var claims = new List<Claim>
{
    new Claim(
        ClaimTypes.NameIdentifier,
        user.UserId.ToString(CultureInfo.InvariantCulture)),

    new Claim(ClaimTypes.Name, user.Username),

    new Claim(
        "security_version",
        user.SecurityVersion.ToString(CultureInfo.InvariantCulture))
};

claims.AddRange(user.Roles.Select(role =>
    new Claim(ClaimTypes.Role, role)));
    var identity = new ClaimsIdentity(
    claims,
    CookieAuthenticationDefaults.AuthenticationScheme);

await HttpContext.SignInAsync(
    CookieAuthenticationDefaults.AuthenticationScheme,
    new ClaimsPrincipal(identity));

    return Ok(new
{
    userId = user.UserId,
    username = user.Username,
    roles = user.Roles
});
}
/* [HttpGet("me")]: tạo đường dẫn GET /api/auth/me.
[Authorize]: chỉ người đã được xác thực mới được sử dụng API này. Tài liệu Microsoft
User: chứa thông tin người dùng mà backend đã đọc và xác thực từ cookie.
FindFirst(...): lấy mã tài khoản rồi chuyển lại thành số.
FindAll(ClaimTypes.Role): lấy danh sách quyền.
NoStore = true: yêu cầu trình duyệt không lưu phản hồi này vào bộ nhớ đệm, giúp tránh dùng lại thông tin tài khoản cũ. */
[HttpGet("me")]
[Authorize]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public IActionResult GetCurrentUser()
{
    var userIdText = User.FindFirst(
        ClaimTypes.NameIdentifier)?.Value;

    if (!long.TryParse(
            userIdText,
            NumberStyles.None,
            CultureInfo.InvariantCulture,
            out var userId) ||
        userId <= 0)
    {
        return Unauthorized();
    }

    return Ok(new
    {
        userId,
        username = User.Identity?.Name,
        roles = User.FindAll(ClaimTypes.Role)
            .Select(claim => claim.Value)
            .ToArray()
    });
}

/* [HttpPost("logout")]: tạo API POST /api/auth/logout.
SignOutAsync(...): yêu cầu trình duyệt xóa cookie đăng nhập. Tài liệu Microsoft
Ok(...): trả thông báo "Đã đăng xuất." cho React.
[AllowAnonymous]: cho phép xử lý đăng xuất cả khi phiên vừa hết hạn. Filter CSRF mình đã viết vẫn kiểm tra mã CSRF của yêu cầu này.
 */
[HttpPost("logout")]
[AllowAnonymous]
public async Task<IActionResult> Logout()
{
    await HttpContext.SignOutAsync(
        CookieAuthenticationDefaults.AuthenticationScheme);

    return Ok(new
    {
        message = "Đã đăng xuất."
    });
}
}