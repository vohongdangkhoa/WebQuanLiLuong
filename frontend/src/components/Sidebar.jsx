import { NavLink } from "react-router";

function Sidebar() {
  return (
    <nav className="app-sidebar" aria-label="Menu chính">
      <NavLink to="/" end>
        Tổng quan
      </NavLink>

      <NavLink to="/employees">Nhân viên</NavLink>
      <NavLink to="/attendance">Chấm công</NavLink>
      <NavLink to="/payroll">Tính lương</NavLink>
      <NavLink to="/requests">Yêu cầu</NavLink>
      <NavLink to="/payments">Thanh toán</NavLink>
      <NavLink to="/payslips">Phiếu lương</NavLink>
      <NavLink to="/reports">Báo cáo</NavLink>
    </nav>
  );
}

export default Sidebar;
