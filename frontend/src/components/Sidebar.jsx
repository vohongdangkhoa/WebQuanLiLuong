import { NavLink } from "react-router";
import useAuth from "../hooks/useAuth";
import { hasRole } from "../utils/format";
import { Icon } from "./ui";
const items = [
  { to: "/", label: "Tổng quan", icon: "dashboard" },
  { to: "/employees", label: "Nhân viên", icon: "employees", roles: ["HR"] },
  { to: "/contracts", label: "Hợp đồng", icon: "requests", roles: ["HR", "PAYROLL", "DIRECTOR"] },
  { to: "/attendance", label: "Chấm công", icon: "attendance" },
  { to: "/requests", label: "Yêu cầu & phê duyệt", icon: "requests" },
  { to: "/payroll", label: "Bảng lương", icon: "payroll", roles: ["PAYROLL", "DIRECTOR"] },
  { to: "/payments", label: "Thanh toán", icon: "payments", roles: ["PAYROLL", "DIRECTOR"] },
  { to: "/bank-accounts", label: "Tài khoản nhận lương", icon: "payments" },
  { to: "/configuration", label: "Thiết lập lương", employeeLabel: "Người phụ thuộc", icon: "payroll" },
  { to: "/payslips", label: "Phiếu lương của tôi", icon: "payslips", roles: ["EMPLOYEE"] },
  { to: "/reports", label: "Báo cáo", icon: "reports", roles: ["PAYROLL", "DIRECTOR"] },
  { to: "/audit", label: "Nhật ký hoạt động", icon: "shield", roles: ["HR", "PAYROLL", "DIRECTOR"] },
  { to: "/settings", label: "Cài đặt tài khoản", icon: "shield" },
];
export default function Sidebar({ onNavigate }) {
  const { user } = useAuth();
  const employeeView = !hasRole(user, "HR", "PAYROLL", "DIRECTOR");
  return <aside className="app-sidebar"><NavLink to="/" className="brand" onClick={onNavigate}><span className="brand-mark"><Icon name="building" size={25} /></span><span>HR<span className="brand-accent">Flow</span><small>NHÂN SỰ & TIỀN LƯƠNG</small></span></NavLink><div className="nav-label">KHÔNG GIAN LÀM VIỆC</div><nav aria-label="Menu chính">{items.filter((item) => !item.roles || hasRole(user, ...item.roles)).map((item) => <NavLink key={item.to} to={item.to} end={item.to === "/"} onClick={onNavigate}><Icon name={item.icon} /><span>{employeeView && item.employeeLabel ? item.employeeLabel : item.label}</span><Icon name="arrow" size={14} className="nav-arrow" /></NavLink>)}</nav><div className="sidebar-footer"><Icon name="shield" /><div><strong>Dữ liệu được bảo vệ</strong><span>Phân quyền theo vai trò</span></div></div></aside>;
}
