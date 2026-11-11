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
      <ResourceState resource={resource}>
        {stats && <div className="stats-grid">
          <StatCard label={management ? "Tổng nhân viên" : "Hồ sơ của bạn"} value={numberText(stats.employeeCount)}
            detail={management ? numberText(stats.activeEmployeeCount) + " người đang làm việc" : undefined} icon="employees" />
          <StatCard label="Kỳ lương đang mở" value={numberText(stats.openPeriodCount)} detail={stats.latestPeriodName} icon="attendance" tone="teal" />
          <StatCard label="Yêu cầu chờ xử lý" value={numberText(stats.pendingRequestCount)} icon="requests" tone="amber" />
          <StatCard label="Thực lĩnh kỳ gần nhất" value={money(stats.latestPayrollNet)} icon="payroll" tone="violet" />
        </div>}
      </ResourceState>
      <Card title="Truy cập nhanh">
        <div className="quick-links">
          {visibleShortcuts.map((item) => (
            <Link key={item.to} to={item.to}>
              <span className="quick-icon"><Icon name={item.icon} size={24} /></span>
              <div><h3>{item.label}</h3><p>{item.text}</p></div>
              <Icon name="arrow" size={18} />
            </Link>
          ))}
        </div>
      </Card>
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