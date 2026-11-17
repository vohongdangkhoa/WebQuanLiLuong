import { Link } from "react-router";
import useAuth from "../hooks/useAuth";
import useResource from "../hooks/useResource";
import { dateText, dateTimeText, roleLabels } from "../utils/format";
import { Button, Card, DataTable, PageHeader, ResourceState, StatusBadge } from "../components/ui";

function Details({ children }) {
  return <dl className="account-details profile-details">{children}</dl>;
}

function Detail({ label, children }) {
  return <div><dt>{label}</dt><dd>{children || "Chưa bổ sung"}</dd></div>;
}

export default function MyProfilePage() {
  const { user } = useAuth();
  const resource = useResource("/profile");
  const profile = resource.data;

  return <>
    <PageHeader title="Hồ sơ cá nhân" description={profile && `${profile.employeeCode} · ${profile.fullName}`}>
      <Link className="button button-secondary" to="/">Về tổng quan</Link>
      <Button variant="secondary" icon="refresh" onClick={resource.reload}>Làm mới</Button>
    </PageHeader>
    <ResourceState resource={resource}>
      {profile && <>
        <Card title="Thông tin cá nhân">
          <Details>
            <Detail label="Mã nhân viên">{profile.employeeCode}</Detail>
            <Detail label="Họ và tên">{profile.fullName}</Detail>
            <Detail label="Ngày sinh">{profile.birthDate ? dateText(profile.birthDate) : null}</Detail>
            <Detail label="Số điện thoại">{profile.phoneNumber}</Detail>
            <Detail label="Email">{profile.email}</Detail>
            <Detail label="Trạng thái làm việc"><StatusBadge value={profile.status} /></Detail>
          </Details>
        </Card>
        <Card title="Thông tin công việc">
          <Details>
            <Detail label="Ngày vào làm">{dateText(profile.hireDate)}</Detail>
            <Detail label="Phòng ban hiện tại">{profile.departmentName || "Chưa phân công"}</Detail>
            <Detail label="Chức danh hiện tại">{profile.positionName || "Chưa phân công"}</Detail>
            <Detail label="Ngày bắt đầu phân công">{dateText(profile.assignmentStart)}</Detail>
            {profile.terminationDate && <Detail label="Ngày cuối cùng làm việc">{dateText(profile.terminationDate)}</Detail>}
          </Details>
        </Card>
        <Card title="Tài khoản đăng nhập">
          <Details>
            <Detail label="Tên đăng nhập">{profile.username}</Detail>
            <Detail label="Vai trò">{user.roles.map((role) => roleLabels[role] || role).join(" · ")}</Detail>
            <Detail label="Ngày cấp tài khoản">{dateTimeText(profile.accountCreatedAt)}</Detail>
          </Details>
          <div className="profile-links">
            <Link className="button button-secondary" to="/settings">Cài đặt tài khoản</Link>
            <Link className="button button-secondary" to="/bank-accounts">Tài khoản nhận lương</Link>
          </div>
        </Card>
        <Card title="Lịch sử phân công">
          <DataTable rows={profile.assignments} rowKey="assignmentId" searchable={false}
            emptyTitle="Chưa có lịch sử phân công" columns={[
              { key: "departmentName", label: "Phòng ban" },
              { key: "positionName", label: "Chức danh" },
              { key: "validFrom", label: "Từ ngày" },
              { key: "validTo", label: "Đến trước ngày", render: (value) => value ? dateText(value) : "Chưa giới hạn" },
            ]} />
        </Card>
        <Card title="Hợp đồng đã được duyệt">
          <DataTable rows={profile.contracts} rowKey="contractId" searchable={false}
            emptyTitle="Chưa có hợp đồng được duyệt" columns={[
              { key: "contractNo", label: "Số hợp đồng" },
              { key: "validFrom", label: "Từ ngày" },
              { key: "validTo", label: "Đến trước ngày", render: (value) => value ? dateText(value) : "Chưa giới hạn" },
              { key: "monthlySalary", label: "Lương tháng", align: "right" },
              { key: "insuranceBase", label: "Mức đóng bảo hiểm", align: "right" },
              { key: "insuranceEnabled", label: "Tham gia bảo hiểm" },
              { key: "calendarName", label: "Lịch làm việc" },
            ]} />
        </Card>
        <p className="section-note">Liên hệ bộ phận nhân sự khi thông tin hồ sơ cần được cập nhật.</p>
      </>}
    </ResourceState>
  </>;
}
