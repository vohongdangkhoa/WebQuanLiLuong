using System.Globalization;
using System.Security.Claims;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Oracle.ManagedDataAccess.Client;
using Payroll.Api.Contracts;
using Payroll.Api.Data;
using Payroll.Api.Services;

namespace Payroll.Api.Controllers;

[ApiController, Authorize, Route("api")]
[ResponseCache(NoStore=true, Location=ResponseCacheLocation.None)]
public sealed class PlatformController(OraclePlatformRepository repository, BankSecurityService security,
    AuthService auth, IPasswordHasher<AuthUser> hasher) : ControllerBase
{
    private long Actor() => long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier),
        NumberStyles.None, CultureInfo.InvariantCulture, out var id) && id>0
        ? id : throw new PlatformException("Phiên đăng nhập không hợp lệ.",401);

    [HttpGet("dashboard")]
    public async Task<IActionResult> Dashboard(CancellationToken ct)
    {
        var actor=Actor();
        var rows=await repository.ReadAsync("dashboard",actor,ct);
        var data=rows.FirstOrDefault() ?? new Dictionary<string,object?>();
        data["recentActivity"]=await repository.ReadAsync("notifications",actor,ct);
        return Ok(data);
    }

    [HttpGet("bank-accounts")]
    public async Task<IActionResult> Banks([FromQuery] long? employeeId,CancellationToken ct)
    {
        if(employeeId is <=0) return BadRequest(new{message="Mã nhân viên không hợp lệ."});
        return Ok(await repository.ReadAsync("bank_accounts",Actor(),ct,("p_employee_id",OracleDbType.Int64,employeeId)));
    }

    [HttpPost("bank-accounts"),Authorize(Roles="HR,EMPLOYEE")]
    public async Task<IActionResult> SaveBank(SaveBankAccountRequest request,CancellationToken ct)
    {
        var account=request.AccountNumber.Trim().ToUpperInvariant();
        var code=request.BankCode.Trim().ToUpperInvariant();
        var id=await repository.WriteAsync("save_bank",Actor(),ct,"p_id",
            ("p_employee_id",OracleDbType.Int64,request.EmployeeId),
            ("p_bank_code",OracleDbType.Varchar2,code),
            ("p_cipher",OracleDbType.Varchar2,security.Encrypt(account)),
            ("p_last4",OracleDbType.Varchar2,account[^4..]),
            ("p_hmac",OracleDbType.Varchar2,security.Fingerprint("BankAccount",code+":"+account)),
            ("p_holder",OracleDbType.Varchar2,request.AccountHolder.Trim()),
            ("p_from",OracleDbType.Date,request.ValidFrom!.Value.ToDateTime(TimeOnly.MinValue)));
        return StatusCode(201,new{bankAccountId=id,message="Đã lưu tài khoản ngân hàng, chờ người có thẩm quyền xác minh."});
    }

    [HttpPost("bank-accounts/{id:long}/decision"),Authorize(Roles="PAYROLL,DIRECTOR")]
    public async Task<IActionResult> DecideBank(long id,BankDecisionRequest request,CancellationToken ct)
    {
        if(id<=0) return BadRequest(new{message="Mã tài khoản ngân hàng không hợp lệ."});
        await repository.WriteAsync("decide_bank",Actor(),ct,null,
            ("p_id",OracleDbType.Int64,id),("p_decision",OracleDbType.Varchar2,request.Decision));
        return Ok(new{message=request.Decision=="VERIFY"?"Đã xác minh tài khoản ngân hàng.":"Đã từ chối tài khoản ngân hàng."});
    }

    [HttpPost("auth/password")]
    public async Task<IActionResult> ChangePassword(ChangePasswordRequest request,CancellationToken ct)
    {
        if(request.CurrentPassword==request.NewPassword)
            return BadRequest(new{message="Mật khẩu mới phải khác mật khẩu hiện tại."});
        var user=await auth.ValidateCredentialsAsync(User.Identity!.Name!,request.CurrentPassword,ct);
        if(user is null || user.UserId!=Actor()) return BadRequest(new{message="Mật khẩu hiện tại không đúng."});
        var updated=await repository.WriteAsync("change_password",user.UserId,ct,"p_updated",
            ("p_old_hash",OracleDbType.Varchar2,user.PasswordHash),
            ("p_version",OracleDbType.Int64,user.SecurityVersion),
            ("p_new_hash",OracleDbType.Varchar2,hasher.HashPassword(user,request.NewPassword)));
        if(updated!=1) return Conflict(new{message="Tài khoản vừa thay đổi. Vui lòng đăng nhập lại."});
        await HttpContext.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);
        return Ok(new{message="Đã đổi mật khẩu. Vui lòng đăng nhập lại."});
    }

    [HttpGet("audit"),Authorize(Roles="HR,PAYROLL,DIRECTOR")]
    public async Task<IActionResult> Audit(CancellationToken ct) =>
        Ok(await repository.ReadAsync("audit_rows",Actor(),ct));
}
