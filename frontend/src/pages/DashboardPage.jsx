import { Link } from "react-router";
import useAuth from "../hooks/useAuth";
import useResource from "../hooks/useResource";
import { money, numberText, dateTimeText, hasRole } from "../utils/format";
import { Button, Card, EmptyState, Icon, PageHeader, ResourceState, StatCard } from "../components/ui";

const shortcuts = [
  { to: "/employees", label: "Nhân viên", text: "Hồ sơ và lịch sử phân công", icon: "employees", roles: ["HR"] },
  { to: "/attendance", label: "Chấm công", text: "Xem ngày công và ca làm việc", icon: "attendance" },
  { to: "/requests", label: "Đơn từ", text: "Nghỉ phép, tăng ca và sửa công", icon: "requests" },
  { to: "/payroll", label: "Bảng lương", text: "Tính lương và gửi duyệt", icon: "payroll", roles: ["PAYROLL", "DIRECTOR"] },
  { to: "/payslips", label: "Phiếu lương", text: "Các khoản thu nhập và khấu trừ", icon: "payslips", roles: ["EMPLOYEE"] },
  { to: "/reports", label: "Báo cáo", text: "Chi phí lương theo kỳ và phòng ban", icon: "reports", roles: ["PAYROLL", "DIRECTOR"] },
];

const personalLinks = [
  { to: "/profile", label: "Hồ sơ cá nhân", description: "Thông tin cá nhân và công việc", action: "Xem hồ sơ", icon: "employees" },
  { to: "/attendance", label: "Chấm công", description: "Ngày công và thời gian làm việc", action: "Xem bảng công", icon: "attendance" },
  { to: "/requests", label: "Đơn từ", description: "Nghỉ phép, tăng ca và điều chỉnh công", action: "Xem đơn từ", icon: "requests" },
  { to: "/payslips", label: "Phiếu lương", description: "Thu nhập, khấu trừ và tiền thực lĩnh", action: "Xem phiếu lương", icon: "payslips" },
];
export default function DashboardPage() {
  const { user } = useAuth();
  const resource = useResource("/dashboard");
  const stats = resource.data;
  const management = hasRole(user, "HR", "PAYROLL", "DIRECTOR");
  const visibleShortcuts = shortcuts.filter((item) => !item.roles || hasRole(user, ...item.roles));

  return (
    <>
      <PageHeader title="Tổng quan">
        <Button variant="secondary" icon="refresh" onClick={resource.reload}>Làm mới</Button>
      </PageHeader>
      {management ? <ResourceState resource={resource}>
        {stats && <div className="stats-grid">
          <StatCard label="Tổng nhân viên" value={numberText(stats.employeeCount)}
            detail={numberText(stats.activeEmployeeCount) + " người đang làm việc"} icon="employees" />
          <StatCard label="Kỳ lương đang mở" value={numberText(stats.openPeriodCount)} icon="attendance" tone="teal" />
          <StatCard label="Yêu cầu chờ xử lý" value={numberText(stats.pendingRequestCount)} icon="requests" tone="amber" />
          <StatCard label="Lương thực lĩnh gần nhất" value={money(stats.latestPayrollNet)}
            detail={stats.latestPayrollNet == null ? "Chưa có phiếu lương được duyệt" : `Kỳ ${stats.latestPeriodName} · Theo bảng lương đã duyệt`}
            icon="payroll" tone="violet" />
        </div>}
      </ResourceState> : (
        <nav className="personal-overview" aria-label="Chức năng cá nhân">
          {personalLinks.map((item) => (
            <Link key={item.to} to={item.to} className="overview-card">
              <span className="overview-card-icon"><Icon name={item.icon} size={24} /></span>
              <h2>{item.label}</h2>
              <p>{item.description}</p>
              <span className="overview-card-action">{item.action}<Icon name="arrow" size={18} /></span>
            </Link>
          ))}
        </nav>
      )}
      {management && <Card title="Truy cập nhanh">
        <div className="quick-links">
          {visibleShortcuts.map((item) => (
            <Link key={item.to} to={item.to}>
              <span className="quick-icon"><Icon name={item.icon} size={24} /></span>
              <div><h3>{item.label}</h3><p>{item.text}</p></div>
              <Icon name="arrow" size={18} />
            </Link>
          ))}
        </div>
      </Card>}
      {stats && <Card title="Thông báo">
        {stats.recentActivity?.length ? (
          <ul className="activity-list">
            {stats.recentActivity.map((item, index) => (
              <li key={item.occurredAt + "-" + index}>
                <span className="activity-dot" />
                <div><strong>{item.title}</strong><p>{item.detail}</p></div>
                <time>{dateTimeText(item.occurredAt)}</time>
              </li>
            ))}
          </ul>
        ) : <EmptyState title="Chưa có thông báo" />}
      </Card>}
    </>
  );
}