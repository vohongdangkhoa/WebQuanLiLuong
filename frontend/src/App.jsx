import DashboardPage from "./pages/DashboardPage.jsx";
import MainLayout from "./layouts/MainLayout.jsx";
import EmployeesPage from "./pages/EmployeesPage.jsx";
import AttendancePage from "./pages/AttendancePage.jsx";
import PayrollPage from "./pages/PayrollPage.jsx";
import RequestsPage from "./pages/RequestsPage.jsx";
import PaymentsPage from "./pages/PaymentsPage.jsx";
import PayslipsPage from "./pages/PayslipsPage.jsx";
import ReportsPage from "./pages/ReportsPage.jsx";
import { Routes, Route } from "react-router";
import "./App.css";

function App() {
  return (
    <MainLayout>
      <Routes>
        <Route path="/" element={<DashboardPage />} />
        <Route path="/employees" element={<EmployeesPage />} />
        <Route path="/attendance" element={<AttendancePage />} />
        <Route path="/payroll" element={<PayrollPage />} />
        <Route path="/requests" element={<RequestsPage />} />
        <Route path="/payments" element={<PaymentsPage />} />
        <Route path="/payslips" element={<PayslipsPage />} />
        <Route path="/reports" element={<ReportsPage />} />
      </Routes>
    </MainLayout>
  );
}

export default App;
