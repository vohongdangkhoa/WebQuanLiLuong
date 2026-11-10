# Kiểm định giao diện HRFlow

Giao diện gọi dữ liệu thật từ API. Không có bộ dữ liệu mẫu hoặc thông báo thành công giả trong các màn hình nghiệp vụ. Các thao tác ghi không tự thử lại. Khóa yêu cầu tính lương, thanh toán và cấp phép được tạo một lần cho mỗi biểu mẫu, giữ nguyên khi thử lại biểu mẫu đó.

## Cách chạy

Backend mặc định `http://localhost:5038`. Trong thư mục `frontend`, dùng `npm.cmd ci`, `npm.cmd run dev`. Trình duyệt truy cập địa chỉ Vite hiện trên terminal. Proxy `/api` trỏ vào backend; có thể đặt `API_PROXY_TARGET` để kiểm tra bằng cổng backend khác. `VITE_API_BASE_URL` chỉ cần khi muốn gọi API ngoài proxy.

Ngày 10/11/2026, `npm.cmd run lint` và `npm.cmd run build` đều thành công với đầy đủ màn hình, bao gồm Thiết lập lương và Người phụ thuộc. Kiểm tra riêng xác nhận nội dung CSV đối soát giữ nguyên dấu BOM UTF-8 khi chuyển qua API.

## Kịch bản trình duyệt cần xác nhận với Oracle

1. HR: đăng nhập, xem nhân viên, lọc/tìm kiếm, tạo hồ sơ mới, phân công lần đầu, mở hồ sơ và kiểm tra lịch sử. Sau F5 dữ liệu vẫn còn. Tạo trùng mã hoặc phân công trước ngày vào làm phải báo lỗi và giữ dữ liệu đã nhập.
2. HR: lập hợp đồng chờ duyệt; giám đốc khác người tạo duyệt; lập lịch tháng và điều chỉnh ngày lễ; phân ca, ghi nhận công có xác nhận, chốt bảng công. Không chốt khi còn dữ liệu hoặc đơn chưa xử lý.
3. Nhân viên: chỉ thấy dữ liệu của chính mình ở chấm công, đơn, tài khoản nhận lương và phiếu lương. Không thể vào màn hình quản trị bằng cách gõ URL trực tiếp.
4. Nhân viên tạo đơn nghỉ/tăng ca; HR khác người tạo duyệt. Đơn nghỉ dùng khoảng ngày không bao gồm ngày kết thúc. Xác nhận thời gian tăng ca thực tế sau phê duyệt.
5. HR hoặc nhân viên thêm tài khoản ngân hàng; kế toán/giám đốc khác người tạo xác minh. Chỉ hiển thị bốn số cuối. Không xuất hiện số tài khoản đầy đủ/cipher/hash trên các API đọc danh sách.
6. Kế toán: tạo kỳ lương; tính lương từ công đã chốt; mở chi tiết và bảng lỗi. Nếu sửa nguồn, tạo phiên bản tính mới. Gửi duyệt; giám đốc khác người tính duyệt. Trạng thái phê duyệt và trạng thái trả tiền được hiển thị riêng.
7. Kế toán: tạo đợt thanh toán; xuất CSV; tải lại tệp phải giữ nguyên snapshot; xác nhận đã gửi ngân hàng; nhập tệp kết quả thực tế. PROCESSING chưa phải đã thanh toán; chỉ SUCCEEDED đã đối soát mới là thành công. Đối soát lệch tiền hoặc trùng tệp phải thể hiện đúng lỗi/trạng thái.
8. Nhân viên mở phiếu lương của chính mình, xem diễn giải, xuất CSV và in. Kế toán/giám đốc kiểm tra báo cáo chỉ gồm phiên bản đã duyệt.
9. Cài đặt: mật khẩu mới hai lần không khớp bị chặn trước khi gửi. Mật khẩu giữ nguyên khoảng trắng do người dùng nhập. Đổi thành công phải kết thúc phiên, trở về đăng nhập.
10. Thu nhỏ trình duyệt: menu chuyển thành nút mở, bảng cuộn ngang, biểu mẫu không tràn màn hình; Escape/X không đóng biểu mẫu khi thao tác ghi đang chạy.

## Những điều đã kiểm tra bằng đọc nguồn

- Menu và route quản trị được chặn theo vai trò; backend vẫn kiểm tra quyền bắt buộc.
- Yêu cầu ghi dùng cookie và CSRF, không gửi actor từ trình duyệt.
- Ngày không kèm giờ được định dạng trực tiếp từ ISO, tránh thay đổi ngày theo múi giờ.
- Thành công ghi dữ liệu và lỗi làm mới danh sách được xử lý riêng.
- CSV xuất tại trình duyệt chống mở ô thành công thức từ tên/lý do/diễn giải.
- Tệp API được đọc dưới dạng blob; phản hồi lỗi vẫn được đọc JSON.
- Không báo thành công khi API trả HTML hoặc dữ liệu không đúng JSON mong đợi.
