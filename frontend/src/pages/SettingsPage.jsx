import useAuth from "../hooks/useAuth";
import { roleLabels } from "../utils/format";
import { Card, PageHeader } from "../components/ui";
import ActionForm from "../components/ActionForm";

const fields = [
  { name: "currentPassword", label: "Mật khẩu hiện tại", type: "password", required: true, maxLength: 50, autoComplete: "current-password" },
  { name: "newPassword", label: "Mật khẩu mới", type: "password", required: true, minLength: 8, maxLength: 50, autoComplete: "new-password" },
  { name: "confirmPassword", label: "Nhập lại mật khẩu mới", type: "password", required: true, minLength: 8, maxLength: 50, autoComplete: "new-password" },
];

export default function SettingsPage() {
  const { user } = useAuth();

  function changePassword(values) {
    if (values.newPassword !== values.confirmPassword)
      throw new Error("Hai lần nhập mật khẩu mới chưa khớp.");
    return { currentPassword: values.currentPassword, newPassword: values.newPassword };
  }

  return (
    <>
      <PageHeader title="Tài khoản" />
      <Card title="Thông tin đăng nhập">
        <div className="card-body">
          <dl className="account-details">
            <div><dt>Tên đăng nhập</dt><dd>{user.username}</dd></div>
            <div><dt>Vai trò</dt><dd>{user.roles.map((role) => roleLabels[role] || role).join(", ")}</dd></div>
          </dl>
        </div>
      </Card>
      <Card title="Đổi mật khẩu" description="Bạn sẽ đăng nhập lại sau khi đổi mật khẩu.">
        <div className="card-body password-form">
          <ActionForm endpoint="/auth/password" submitLabel="Đổi mật khẩu"
            warning="Mật khẩu mới cần từ 8 đến 50 ký tự." fields={fields}
            transform={changePassword} onSuccess={() => window.dispatchEvent(new Event("payroll:session-expired"))} />
        </div>
      </Card>
    </>
  );
}