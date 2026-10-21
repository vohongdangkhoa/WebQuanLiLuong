import { Outlet } from "react-router"; /* <Outlet /> là chỗ React Router đặt nội dung trang con. Ví dụ: vào /employees thì EmployeesPage xuất hiện tại đó. Tài liệu React Router */
import Header from "../components/Header.jsx";
import Sidebar from "../components/Sidebar.jsx";

function MainLayout() {
  return (
    <div className="app-layout">
      <Header />

      <div className="app-body">
        <Sidebar />

        <div className="app-content">
          <Outlet />
        </div>
      </div>
    </div>
  );
}

export default MainLayout;
