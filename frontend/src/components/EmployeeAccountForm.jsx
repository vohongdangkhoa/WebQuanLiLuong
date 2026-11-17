import { useState } from "react";
import useResource from "../hooks/useResource";
import { apiPost } from "../services/api";
import { dateText } from "../utils/format";
import { Alert, Button, Field, Icon, ResourceState } from "./ui";

export default function EmployeeAccountForm({ employeeId, onSaved, onBusyChange }) {
  const resource = useResource(`/employees/${employeeId}/account`);
  const [created, setCreated] = useState(null);
  const [busy, setBusy] = useState(false);

  function changeBusy(value) {
    setBusy(value);
    onBusyChange(value);
  }

  return (
    <>
      <div className="section-toolbar">
        <p className="section-note">Mỗi nhân viên có một tài khoản gắn với hồ sơ của mình.</p>
        {!created && <Button variant="secondary" disabled={busy} onClick={resource.reload}>Tải lại</Button>}
      </div>
      {created ? <AccountCredentials account={created} /> : (
        <ResourceState resource={resource}>
          {resource.data && <AccountDetails
            key={resource.data.rowVersion}
            profile={resource.data}
            onBusyChange={changeBusy}
            onCreated={(account) => {
              setCreated(account);
              onSaved();
            }}
          />}
        </ResourceState>
      )}
    </>
  );
}

function AccountDetails({ profile, onCreated, onBusyChange }) {
  const [phoneNumber, setPhoneNumber] = useState(profile.phoneNumber || "");
  const [birthDate, setBirthDate] = useState(profile.birthDate || "");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const suffix = profile.employeeCode.slice(-2);
  const validCode = /^[0-9]{2}$/.test(suffix);
  const username = validCode && /^0[0-9]{9}$/.test(phoneNumber) ? suffix + phoneNumber : "";

  if (profile.userId) {
    return <div className="detail-grid">
      <div><span>Tên đăng nhập</span><strong>{profile.username}</strong></div>
      <div><span>Trạng thái tài khoản</span><strong>{profile.accountActive ? "Đang hoạt động" : "Đã khóa"}</strong></div>
      <div><span>Số điện thoại</span><strong>{profile.phoneNumber || "Chưa bổ sung"}</strong></div>
      <div><span>Ngày sinh</span><strong>{dateText(profile.birthDate)}</strong></div>
    </div>;
  }
  if (profile.status !== "ACTIVE" || profile.terminationDate) {
    return <Alert>Chỉ cấp tài khoản cho nhân viên đang làm việc.</Alert>;
  }
  if (!validCode) {
    return <Alert>Mã nhân viên phải kết thúc bằng hai chữ số để tạo tên đăng nhập theo quy tắc.</Alert>;
  }

  async function submit(event) {
    event.preventDefault();
    if (busy) return;
    setBusy(true);
    onBusyChange(true);
    setError("");
    try {
      const account = await apiPost(`/employees/${profile.employeeId}/account`, {
        phoneNumber, birthDate, rowVersion: profile.rowVersion,
      });
      onCreated(account);
    } catch (failure) {
      setError(failure.message);
    } finally {
      setBusy(false);
      onBusyChange(false);
    }
  }

  return <form onSubmit={submit} className="action-form">
    <fieldset disabled={busy}>
      <div className="form-grid">
        <Field label="Số điện thoại *" hint="Gồm 10 chữ số, bắt đầu bằng 0. Được lưu vào hồ sơ khi cấp tài khoản.">
          {(id) => <input id={id} type="tel" autoComplete="tel" inputMode="numeric"
            required pattern="0[0-9]{9}" minLength={10} maxLength={10}
            value={phoneNumber} onChange={(event) => setPhoneNumber(event.target.value)} />}
        </Field>
        <Field label="Ngày sinh *" hint={profile.birthDate ? "Ngày sinh lấy từ hồ sơ. Có thể sửa tại mục Thông tin cá nhân." : "Bổ sung ngày sinh chính xác của nhân viên để tạo mật khẩu."}>
          {(id) => <input id={id} type="date" required readOnly={Boolean(profile.birthDate)}
            max={profile.hireDate} value={birthDate} onChange={(event) => setBirthDate(event.target.value)} />}
        </Field>
        <Field label="Tên đăng nhập" hint="Hai số cuối mã nhân viên ghép với số điện thoại.">
          {(id) => <input id={id} value={username} readOnly placeholder="Nhập số điện thoại để xem" />}
        </Field>
        <div className="field">
          <span>Vai trò được cấp</span>
          <div className="employee-account-role"><Icon name="shield" size={18} /><strong>Nhân viên</strong></div>
          <small>Quyền này được gán tự động khi HR cấp tài khoản.</small>
        </div>
      </div>
    </fieldset>
    <p className="form-note">Mật khẩu ban đầu gồm ngày sinh dạng ddMMyyyy, dấu @ và toàn bộ họ tên bỏ dấu, bỏ khoảng trắng. Chữ đầu mỗi từ viết hoa. Ví dụ 06092004@NguyenVanAn.</p>
    <Alert>{error}</Alert>
    <div className="form-actions">
      <Button type="submit" disabled={busy || !username || !birthDate} icon="plus">
        {busy ? "Đang cấp tài khoản…" : "Cấp tài khoản nhân viên"}
      </Button>
    </div>
  </form>;
}

function AccountCredentials({ account }) {
  const [showPassword, setShowPassword] = useState(false);
  const [copied, setCopied] = useState(false);
  const [copyError, setCopyError] = useState("");

  async function copy() {
    try {
      await navigator.clipboard.writeText(`Tên đăng nhập: ${account.username}\nMật khẩu ban đầu: ${account.initialPassword}`);
      setCopied(true);
      setCopyError("");
    } catch {
      setCopyError("Chưa sao chép được. Bấm Hiện mật khẩu để xem và ghi lại thông tin.");
    }
  }

  return <>
    <Alert type="success">Đã cấp tài khoản Nhân viên. Hãy chuyển thông tin đăng nhập cho đúng nhân viên.</Alert>
    <div className="form-grid">
      <Field label="Tên đăng nhập">{(id) => <input id={id} value={account.username} readOnly />}</Field>
      <Field label="Mật khẩu ban đầu">{(id) => <input id={id} type={showPassword ? "text" : "password"} value={account.initialPassword} autoComplete="off" readOnly />}</Field>
    </div>
    <p className="section-note">Mật khẩu ban đầu chỉ hiện trong lần cấp này. Nhân viên có thể đổi mật khẩu tại mục Tài khoản sau khi đăng nhập.</p>
    <Alert>{copyError}</Alert>
    <div className="form-actions">
      <Button variant="secondary" onClick={() => setShowPassword(!showPassword)}>{showPassword ? "Ẩn mật khẩu" : "Hiện mật khẩu"}</Button>
      <Button onClick={copy}>{copied ? "Đã sao chép" : "Sao chép thông tin đăng nhập"}</Button>
    </div>
  </>;
}
