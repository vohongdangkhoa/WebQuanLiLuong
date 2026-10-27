import { useState } from "react";
import useAuth from "../hooks/useAuth";

function Header() {
  const { user, signOut } = useAuth();
  const [isSigningOut, setIsSigningOut] = useState(false);
  const [logoutError, setLogoutError] = useState("");

  async function handleLogout() {
    if (isSigningOut) return;

    setLogoutError("");
    setIsSigningOut(true);

    try {
      await signOut();
    } catch (error) {
      setLogoutError(
        error.message || "Không đăng xuất được. Vui lòng thử lại.",
      );
    } finally {
      setIsSigningOut(false);
    }
  }

  return (
    <header className="app-header">
      <strong>Quản lý nhân sự và tính lương</strong>

      <div className="header-account">
        <span>Xin chào bạn, {user?.username}</span>

        <button type="button" onClick={handleLogout} disabled={isSigningOut}>
          {isSigningOut ? "Đang đăng xuất..." : "Đăng xuất"}
        </button>
      </div>

      {logoutError && <p role="alert">{logoutError}</p>}
    </header>
  );
}

export default Header;
/* useAuth(): lấy thông tin đăng nhập mà AuthProvider đang giữ.
const { user }: lấy riêng thông tin tài khoản.
{user?.username}: hiển thị tên đăng nhập. Dấu ?. giúp tránh lỗi nếu user chưa có giá trị. */

/* isSigningOut: ghi nhớ đang chờ đăng xuất hay chưa.
onClick={handleLogout}: nhấn nút thì chạy hàm handleLogout.
disabled={isSigningOut}: tạm khóa nút trong lúc chờ.
await signOut(): chờ backend xử lý đăng xuất. Thành công thì AuthProvider đặt user về null, và ProtectedRoute tự chuyển sang /login.
catch: nếu đăng xuất gặp lỗi, hiện thông báo để bạn biết. */
