import { StrictMode } from "react";

/* Bạn hiểu đơn giản: AuthProvider bọc bên ngoài App, nên App và các trang bên trong có thể gọi useAuth() để nhận thông tin tài khoản, hàm đăng nhập và hàm đăng xuất.
Khi React mở lên, AuthProvider cũng bắt đầu gọi backend để kiểm tra phiên. Vì vậy, backend cần chạy tại http://localhost:5038
 */
import AuthProvider from "./contexts/AuthProvider.jsx";
import { createRoot } from "react-dom/client";
import { BrowserRouter } from "react-router";
import "./index.css";
import App from "./App.jsx";

createRoot(document.getElementById("root")).render(
  <StrictMode>
    <BrowserRouter>
      <AuthProvider>
        <App />
      </AuthProvider>
    </BrowserRouter>
  </StrictMode>,
);
