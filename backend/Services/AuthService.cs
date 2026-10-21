using Microsoft.AspNetCore.Identity;
using Payroll.Api.Data;

namespace Payroll.Api.Services;

public class AuthService
{
    private readonly OracleAuthRepository _authRepository;
    private readonly IPasswordHasher<AuthUser> _passwordHasher;

    public AuthService(
        OracleAuthRepository authRepository,
        IPasswordHasher<AuthUser> passwordHasher)
    {
        _authRepository = authRepository;
        _passwordHasher = passwordHasher;
    }

    /*hàm kiểm tra tên đăng nhập và mật khẩu.*/
    public async Task<AuthUser?> ValidateCredentialsAsync(
    string username,
    string password,
    CancellationToken cancellationToken = default)
{
    if (string.IsNullOrWhiteSpace(username) ||
        string.IsNullOrEmpty(password))
    {
        return null;
    }

    var normalizedUsername = username.Trim().ToLowerInvariant();

    var user = await _authRepository.FindForLoginAsync(
        normalizedUsername, cancellationToken);

    if (user is null || !user.IsActive)
    {
        return null;
    }

    PasswordVerificationResult result;

    try
    {
        result = _passwordHasher.VerifyHashedPassword(
            user, user.PasswordHash, password);
    }
    catch (FormatException)
    {
        return null;
    }

    if (result != PasswordVerificationResult.Success &&
        result != PasswordVerificationResult.SuccessRehashNeeded)
    {
        return null;
    }

    if (result == PasswordVerificationResult.SuccessRehashNeeded)
    {
        var newHash = _passwordHasher.HashPassword(user, password);

        var updated = await _authRepository.TryRehashPasswordAsync(
            user, newHash, cancellationToken);

        if (!updated)
        {
            return null;
        }

        user.PasswordHash = newHash;
    }

    return user;
}
}