import { useState } from "react";
import { Navigate, useLocation } from "react-router";
import useAuth from "../hooks/useAuth";
import { Alert, Button, Field, Icon, Loading } from "../components/ui";

export default function LoginPage() {
  const { user, signIn, isChecking, sessionError, retrySession } = useAuth();
  const location = useLocation();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function submit(event) {
    event.preventDefault();
    if (busy) return;
    setBusy(true);
    setError("");
    try {
      await signIn(username, password);
    } catch (failure) {
      setError(failure.message);
    } finally {
      setBusy(false);
    }
  }

  if (isChecking) return <div className="session-screen"><Loading text="Đang kiểm tra đăng nhập…" /></div>;
  if (user) return <Navigate to={location.state?.from || "/"} replace />;

  return (
    <main className="login-page">
      <section className="login-story">
        <div className="login-brand"><span className="brand-mark"><Icon name="building" size={28} /></span><span>HRFlow</span></div>
        <div className="login-story-copy">
          <h1>Quản lý nhân sự và tiền lương</h1>
          <p>Hồ sơ nhân viên, chấm công, tính lương và thanh toán.</p>
        </div>
      </section>
      <section className="login-form-side">
        <div className="login-card">
          <p className="login-mobile-brand">HRFlow</p>
          <h2>Đăng nhập</h2>
          <p>Dùng tài khoản công ty để đăng nhập.</p>
          {sessionError ? <><Alert>{sessionError}</Alert><Button onClick={retrySession}>Thử lại</Button></> : (
            <form onSubmit={submit}>
              <fieldset disabled={busy}>
                <Field label="Tên đăng nhập">{(id) => (
                  <input id={id} name="username" autoComplete="username" required maxLength={50}
                    value={username} onChange={(event) => setUsername(event.target.value)} />
                )}</Field>
                <div className="field">
                  <label className="login-password-label" htmlFor="login-password">Mật khẩu</label>
                  <div className="password-field">
                    <input id="login-password" name="password" type={showPassword ? "text" : "password"}
                      autoComplete="current-password" required maxLength={50} value={password}
                      onChange={(event) => setPassword(event.target.value)} />
                    <button type="button" aria-label={showPassword ? "Ẩn mật khẩu" : "Hiện mật khẩu"}
                      onClick={() => setShowPassword(!showPassword)}>{showPassword ? "Ẩn" : "Hiện"}</button>
                  </div>
                </div>
              </fieldset>
              <Alert>{error}</Alert>
              <Button type="submit" className="login-submit" disabled={busy}>{busy ? "Đang đăng nhập…" : "Đăng nhập"}</Button>
            </form>
          )}
        </div>
      </section>
    </main>
  );
}
