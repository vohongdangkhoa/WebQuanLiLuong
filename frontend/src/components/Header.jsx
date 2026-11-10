import { useState } from "react";
import { useLocation } from "react-router";
import useAuth from "../hooks/useAuth";
import { hasRole, roleLabels } from "../utils/format";
import { Alert, Icon } from "./ui";
const titles = { "/": "Tổng quan", "/employees": "Nhân viên", "/contracts": "Hợp đồng", "/attendance": "Chấm công", "/requests": "Yêu cầu & phê duyệt", "/payroll": "Bảng lương", "/payments": "Thanh toán", "/payslips": "Phiếu lương", "/reports": "Báo cáo", "/bank-accounts": "Tài khoản nhận lương", "/audit": "Nhật ký hoạt động", "/settings": "Cài đặt tài khoản", "/configuration": "Thiết lập lương" };
export default function Header({ onMenu }) {
  const { user, signOut } = useAuth(); const location = useLocation(); const [busy, setBusy] = useState(false); const [error, setError] = useState("");
  const title = location.pathname === "/configuration" && !hasRole(user, "HR", "PAYROLL", "DIRECTOR")
    ? "Người phụ thuộc"
    : titles[location.pathname] || "Chi tiết";
  async function logout() { if (busy) return; setBusy(true); setError(""); try { await signOut(); } catch (failure) { setError(failure.message); } finally { setBusy(false); } }
  return <><header className="app-header"><div className="header-left"><button type="button" className="icon-button mobile-menu" aria-label="Mở menu" onClick={onMenu}><Icon name="menu" /></button><div className="breadcrumb">Không gian làm việc<Icon name="arrow" size={13} /><strong>{title}</strong></div></div><div className="header-account"><span className="avatar">{user?.username?.slice(0, 2).toUpperCase()}</span><div className="account-info"><strong>{user?.username}</strong><small>{user?.roles?.map((role) => roleLabels[role] || role).join(" · ")}</small></div><button type="button" className="icon-button logout-button" title="Đăng xuất" aria-label="Đăng xuất" disabled={busy} onClick={logout}><Icon name="logout" /></button></div></header>{error && <div className="header-error"><Alert onClose={() => setError("")}>{error}</Alert></div>}</>;
}
