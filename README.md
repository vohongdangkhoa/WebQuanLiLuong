# HRFlow

Ứng dụng quản lý nhân sự và tính lương dùng React, ASP.NET Core .NET 10 và Oracle Free.

## Mở ứng dụng trên Windows

1. Bật Docker Desktop và chạy container Oracle của dự án.
2. Mở `Mo-Web.cmd` trong thư mục gốc. Lần đầu script sẽ cài thư viện frontend nếu cần, build React và backend, rồi mở trình duyệt. Địa chỉ mặc định là `http://localhost:5049`. Nếu cổng bận, script in địa chỉ được chọn trong terminal.
3. Đăng nhập bằng tài khoản web hiện có. Backend dùng chuỗi kết nối Oracle `ConnectionStrings:Oracle` đã cấu hình trong .NET User Secrets hoặc biến môi trường.

Nếu đang chạy `dotnet run` và `npm.cmd run dev` riêng, dùng địa chỉ Vite in trong terminal. Proxy `/api` mặc định trỏ đến `http://localhost:5038`.

Khi chuyển sang cơ sở dữ liệu khác đã có schema của dự án, dùng `scripts/Update-Database.ps1` để áp dụng các nâng cấp từ `16_platform.sql` đến `20_payroll_withdraw.sql`. Giữ thư mục `backend/.local` của bản đang sử dụng để bảo toàn khóa mã hóa và tệp đã tải lên.

## Kiểm định

- React đã qua lint và build. Backend đã build Release thành công.
- Oracle đã qua kiểm thử tính lương, phê duyệt, thanh toán, đối soát và phân quyền đọc. Các ca kiểm thử ghi dùng rollback.
- Đã kiểm tra trang đăng nhập và các endpoint trước đăng nhập. Các bước kiểm định bằng tài khoản hiện có nằm trong [kịch bản giao diện](docs/FRONTEND_QA.md).
