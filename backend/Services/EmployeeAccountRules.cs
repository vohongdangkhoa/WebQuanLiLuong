using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace Payroll.Api.Services;

public static class EmployeeAccountRules
{
    public static string Username(string employeeCode, string phoneNumber)
    {
        if (!Regex.IsMatch(employeeCode, @"[0-9]{2}\z") ||
            !Regex.IsMatch(phoneNumber, @"\A0[0-9]{9}\z"))
            throw new PlatformException("Mã nhân viên phải kết thúc bằng hai chữ số. Số điện thoại cần 10 chữ số và bắt đầu bằng 0.", 400);

        return employeeCode[^2..] + phoneNumber;
    }

    public static string InitialPassword(DateOnly birthDate, string fullName)
    {
        var words = Regex.Split(fullName.Trim(), @"\s+");
        var name = new StringBuilder();
        foreach (var word in words)
        {
            var normalized = word.Replace('Đ', 'D').Replace('đ', 'd').Normalize(NormalizationForm.FormD);
            var letters = new StringBuilder();
            foreach (var character in normalized)
            {
                if (CharUnicodeInfo.GetUnicodeCategory(character) == UnicodeCategory.NonSpacingMark)
                    continue;
                if (!char.IsAsciiLetter(character))
                    throw new PlatformException("Họ tên cần gồm các chữ cái tiếng Việt hoặc chữ Latin để tạo mật khẩu theo quy tắc.", 400);
                letters.Append(character);
            }
            if (letters.Length > 0)
                name.Append(char.ToUpperInvariant(letters[0])).Append(letters.ToString()[1..].ToLowerInvariant());
        }

        var password = birthDate.ToString("ddMMyyyy", CultureInfo.InvariantCulture) + "@" + name;
        if (name.Length == 0 || password.Length > 50)
            throw new PlatformException("Họ tên sau khi bỏ dấu và khoảng trắng cần từ 1 đến 41 chữ cái để mật khẩu không quá 50 ký tự.", 400);
        return password;
    }
}
