import { Navigate, Outlet, useLocation } from "react-router";
import useAuth from "../hooks/useAuth";
import { Alert, Button, EmptyState, Loading } from "./ui";
import { hasRole } from "../utils/format";
export default function ProtectedRoute({ roles }) {
  const { user, isChecking, sessionError, retrySession } = useAuth(); const location = useLocation();
  if (isChecking) return <div className="session-screen"><Loading text="Đang xác nhận phiên đăng nhập…" /></div>;
  if (sessionError) return <div className="session-screen"><Alert>{sessionError}</Alert><Button onClick={retrySession}>Kết nối lại</Button></div>;
  if (!user) return <Navigate to="/login" state={{ from: location.pathname }} replace />;
  if (roles && !hasRole(user, ...roles)) return <EmptyState title="Bạn không có quyền truy cập mục này" description="Chọn một chức năng phù hợp trong menu bên trái." />;
  return <Outlet />;
}
