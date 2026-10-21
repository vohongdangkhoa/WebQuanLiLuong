import { Navigate, Outlet } from "react-router";
import useAuth from "../hooks/useAuth";

export default function ProtectedRoute() {
  /*  - useAuth(): lấy thông tin tài khoản từ AuthProvider.
- !user: dấu ! là phủ định; điều kiện này đúng khi chưa có tài khoản đăng nhập.
- <Navigate to="/login" replace />: chuyển về trang đăng nhập.
- <Outlet />: hiển thị route con khi đã có tài khoản đăng nhập.
AuthProvider đã đảm nhiệm phần chờ kiểm tra phiên, nên thành phần này chỉ cần xét user.             
 */
  const { user } = useAuth();

  if (!user) {
    return <Navigate to="/login" replace />;
  }

  return <Outlet />;
}
