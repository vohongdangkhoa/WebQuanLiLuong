using Microsoft.AspNetCore.Authentication.Cookies;
using Payroll.Api.Data;
using System.Globalization;
using System.Security.Claims;
using Microsoft.AspNetCore.Authentication;

namespace Payroll.Api.Services;

public class PayrollCookieEvents : CookieAuthenticationEvents
{
    private readonly OracleAuthRepository _authRepository;

    public PayrollCookieEvents(
        OracleAuthRepository authRepository)
    {
        _authRepository = authRepository;
    }
    public override async Task ValidatePrincipal(
    CookieValidatePrincipalContext context)
{
    var principal = context.Principal;

    var userIdText = principal?
        .FindFirst(ClaimTypes.NameIdentifier)?.Value;

    var versionText = principal?
        .FindFirst("security_version")?.Value;

    if (principal?.Identity?.IsAuthenticated != true ||
        !long.TryParse(
            userIdText,
            NumberStyles.None,
            CultureInfo.InvariantCulture,
            out var userId) ||
        userId <= 0 ||
        !long.TryParse(
            versionText,
            NumberStyles.None,
            CultureInfo.InvariantCulture,
            out var securityVersion) ||
        securityVersion <= 0)
    {
        context.RejectPrincipal();

        await context.HttpContext.SignOutAsync(
            context.Scheme.Name);

        return;
    }
    /*phần lấy tài khoản từ Oracle để kiểm tra phiên đăng nhập.*/
    var user = await _authRepository.FindForSessionAsync(
    userId,
    context.HttpContext.RequestAborted);

if (user is null ||
    !user.IsActive ||
    user.SecurityVersion != securityVersion)
{
    context.RejectPrincipal();

    await context.HttpContext.SignOutAsync(
        context.Scheme.Name);

    return;
}
var cookieRoles = principal.FindAll(ClaimTypes.Role)
    .Select(claim => claim.Value)
    .ToHashSet(StringComparer.Ordinal);

if (!cookieRoles.SetEquals(user.Roles))
{
    context.RejectPrincipal();

    await context.HttpContext.SignOutAsync(
        context.Scheme.Name);

    return;
}
}
}