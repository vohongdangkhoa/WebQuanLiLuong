import { useState } from "react";
import useAuth from "../hooks/useAuth";
import { Navigate } from "react-router";

export default function LoginPage() {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");

  /* isSubmitting: đang gửi yêu cầu đăng nhập hay không.
loginError: thông báo lỗi đăng nhập.
signIn: hàm đăng nhập lấy từ AuthProvider. */

  const [isSubmitting, setIsSubmitting] = useState(false);
  const [loginError, setLoginError] = useState("");

  const { user, signIn } = useAuth();

  /* event.preventDefault(): ngăn trình duyệt tự gửi biểu mẫu và tải lại trang.
if (isSubmitting): chặn gửi thêm khi yêu cầu trước đang được xử lý.
setLoginError(""): xóa thông báo lỗi cũ.
await signIn(...): gửi tên đăng nhập và mật khẩu đến backend.
catch: lưu thông báo nếu đăng nhập thất bại.
finally: kết thúc trạng thái đang gửi. */

  async function handleSubmit(event) {
    event.preventDefault();
    if (isSubmitting) {
      return;
    }

    setLoginError("");
    setIsSubmitting(true);

    try {
      await signIn(username, password);
    } catch (error) {
      setLoginError(error.message || "Đăng nhập không thành công.");
    } finally {
      setIsSubmitting(false);
    }
  }

  /* - Đăng nhập thành công → AuthProvider cập nhật user.
- LoginPage nhận được user mới và chạy lại.
- if (user) đúng → chuyển sang đường dẫn /, tức trang Tổng quan.
Trong <Navigate />, to="/" là địa chỉ cần chuyển đến; replace thay mục hiện tại trong lịch sử trình duyệt bằng địa chỉ mới */

  if (user) {
    return <Navigate to="/" replace />;
  }
  /* LoginPage: component đại diện cho trang đăng nhập.
main: phần nội dung chính của trang.
section: gom nội dung của khung đăng nhập.
className: đặt tên để mình viết CSS trang trí sau.
aria-labelledby="login-title": dùng tiêu đề có id="login-title" làm tên cho phần này, giúp công cụ đọc màn hình nhận biết. */
  return (
    <main className="login-page">
      <section className="login-card" aria-labelledby="login-title">
        <h1 id="login-title">Đăng nhập</h1>
        <p>Hệ thống quản lý nhân sự và tính lương</p>

        {/* value: nội dung hiện trong ô nhập.
onChange: mỗi khi bạn gõ, lưu nội dung mới vào biến tương ứng.
maxLength={50}: cho nhập tối đa 50 ký tự.
required: yêu cầu nhập nội dung khi gửi biểu mẫu.
type="password": che các ký tự mật khẩu.
htmlFor trùng với id: liên kết nhãn với đúng ô nhập. */}

        <form onSubmit={handleSubmit}>
          <div className="login-field">
            <label htmlFor="login-username">Tên đăng nhập</label>

            <input
              id="login-username"
              name="username"
              type="text"
              autoComplete="username"
              maxLength={50}
              disabled={isSubmitting}
              required
              value={username}
              onChange={(event) => setUsername(event.target.value)}
            />
          </div>

          <div className="login-field">
            <label htmlFor="login-password">Mật khẩu</label>

            <input
              id="login-password"
              name="password"
              type="password"
              autoComplete="current-password"
              maxLength={50}
              disabled={isSubmitting}
              required
              value={password}
              onChange={(event) => setPassword(event.target.value)}
            />
          </div>

          {/* loginError && (...): có thông báo lỗi thì hiển thị nó.
type="submit": bấm nút sẽ gửi biểu mẫu và gọi handleSubmit.
disabled={isSubmitting}: tạm khóa nút khi đang gửi.
Dòng chữ trên nút đổi thành “Đang đăng nhập...” trong lúc chờ backend. */}

          {loginError && (
            <p className="login-error" role="alert">
              {loginError}
            </p>
          )}

          <button
            className="login-submit"
            type="submit"
            disabled={isSubmitting}
          >
            {isSubmitting ? "Đang đăng nhập..." : "Đăng nhập"}
          </button>
        </form>
      </section>
    </main>
  );
}
