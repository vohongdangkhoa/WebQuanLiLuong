using System.Text;
using Microsoft.AspNetCore.Identity;

var password = ReadPassword("Nhập mật khẩu (tối đa 50 ký tự): ");

if (string.IsNullOrWhiteSpace(password) || password.Length > 50)
{
    Console.Error.WriteLine("Mật khẩu cần có nội dung và tối đa 50 ký tự.");
    Environment.ExitCode = 1;
    return;
}

/* Đoạn mới này nằm phía trên dòng static string ReadPassword(string prompt), cùng khu vực với phần nhập mật khẩu đầu tiên.
Giải thích:
- confirmation: giữ mật khẩu nhập lần thứ hai.
- password != confirmation: nếu hai lần khác nhau, chương trình báo lỗi và dừng. Chữ hoa và chữ thường cũng được phân biệt.
- PasswordHasher<object>: tạo công cụ băm mật khẩu.
- HashPassword(...): tạo chuỗi băm theo định dạng mà backend đang sử dụng. Tài liệu Microsoft
- Console.WriteLine(hash): in chuỗi băm để dùng khi cập nhật tài khoản trong Oracle */

var confirmation = ReadPassword("Nhập lại mật khẩu: ");

if (password != confirmation)
{
    Console.Error.WriteLine("Hai lần nhập mật khẩu không giống nhau.");
    Environment.ExitCode = 1;
    return;
}

var hasher = new PasswordHasher<object>();
var hash = hasher.HashPassword(new object(), password);

Console.Error.WriteLine("Chuỗi băm mật khẩu:");
Console.WriteLine(hash);

static string ReadPassword(string prompt)
{
    Console.Error.Write(prompt);
    var input = new StringBuilder();

    while (true)
    {
        var key = Console.ReadKey(intercept: true);

        if (key.Key == ConsoleKey.Enter)
        {
            Console.Error.WriteLine();
            return input.ToString();
        }

        if (key.Key == ConsoleKey.Backspace)
        {
            if (input.Length > 0)
            {
                input.Length--;
                Console.Error.Write("\b \b");
            }

            continue;
        }

        if (!char.IsControl(key.KeyChar))
        {
            input.Append(key.KeyChar);
            Console.Error.Write("*");
        }
    }
}

/* 
ReadPassword(...): khi chạy chương trình, bạn sẽ nhập mật khẩu trong Terminal.
StringBuilder: gom những ký tự bạn gõ thành một chuỗi.
ReadKey(intercept: true): đọc phím nhưng ẩn ký tự thật; chương trình tự hiện dấu *. Tài liệu Microsoft
Nhấn Enter: kết thúc nhập và trả về mật khẩu.
Nhấn Backspace: xóa một ký tự cùng dấu * tương ứng.
Phần if đầu chương trình: sau khi nhập xong, từ chối mật khẩu rỗng, toàn khoảng trắng hoặc dài hơn 50 ký tự. */