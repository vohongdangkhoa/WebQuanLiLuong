using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.DataProtection;

namespace Payroll.Api.Services;

public sealed class BankSecurityService(
    IConfiguration configuration, IWebHostEnvironment environment,
    IDataProtectionProvider protection)
{
    private readonly object _gate = new();
    public void EnsureDevelopmentKey()
    {
        if (!environment.IsDevelopment() || !string.IsNullOrWhiteSpace(configuration["BankEncryptionKey"])) return;
        lock (_gate)
        {
            if (!string.IsNullOrWhiteSpace(configuration["BankEncryptionKey"])) return;
            var folder = Path.Combine(environment.ContentRootPath, ".local");
            Directory.CreateDirectory(folder);
            var path = Path.Combine(folder, "bank-key.protected");
            var protector = protection.CreateProtector("Payroll.BankKey.v1");
            string key;
            if (File.Exists(path)) key = protector.Unprotect(File.ReadAllText(path));
            else
            {
                key = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32));
                File.WriteAllText(path, protector.Protect(key));
            }
            configuration["BankEncryptionKey"] = key;
        }
    }
    private byte[] Key()
    {
        try
        {
            var key = Convert.FromBase64String(configuration["BankEncryptionKey"] ?? "");
            if (key.Length == 32) return key;
        }
        catch (FormatException) { }
        throw new PlatformException("Chưa cấu hình khóa bảo vệ tài khoản ngân hàng.", 503);
    }
    public string Encrypt(string account)
    {
        var nonce = RandomNumberGenerator.GetBytes(12);
        var plain = Encoding.UTF8.GetBytes(account);
        var cipher = new byte[plain.Length];
        var tag = new byte[16];
        using var aes = new AesGcm(Key(), 16);
        aes.Encrypt(nonce, plain, cipher, tag);
        return $"v1:{Convert.ToBase64String(nonce)}:{Convert.ToBase64String(cipher)}:{Convert.ToBase64String(tag)}";
    }
    public string Fingerprint(string purpose, string value)
    {
        var derived = HMACSHA256.HashData(Key(), Encoding.UTF8.GetBytes("Payroll.Fingerprint." + purpose));
        return Convert.ToHexString(HMACSHA256.HashData(derived, Encoding.UTF8.GetBytes(value)));
    }
}
