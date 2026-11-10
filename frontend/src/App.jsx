import { Routes, Route, Link } from "react-router";
import ProtectedRoute from "./components/ProtectedRoute";
import MainLayout from "./layouts/MainLayout";
import LoginPage from "./pages/LoginPage";
import DashboardPage from "./pages/DashboardPage";
import EmployeesPage from "./pages/EmployeesPage";
import ContractsPage from "./pages/ContractsPage";
import AttendancePage from "./pages/AttendancePage";
import PayrollPage from "./pages/PayrollPage";
import RequestsPage from "./pages/RequestsPage";
import PaymentsPage from "./pages/PaymentsPage";
import PayslipsPage from "./pages/PayslipsPage";
import ReportsPage from "./pages/ReportsPage";
import BankAccountsPage from "./pages/BankAccountsPage";
import SettingsPage from "./pages/SettingsPage";
import AuditPage from "./pages/AuditPage";
import ConfigurationPage from "./pages/ConfigurationPage";
import { EmptyState } from "./components/ui";
import "./App.css";
export default function App() {
  return <Routes>
    <Route path="/login" element={<LoginPage />} />
    <Route element={<ProtectedRoute />}>
      <Route element={<MainLayout />}>
        <Route index element={<DashboardPage />} />
        <Route element={<ProtectedRoute roles={["HR"]} />}><Route path="employees" element={<EmployeesPage />} /></Route>
        <Route element={<ProtectedRoute roles={["HR", "PAYROLL", "DIRECTOR"]} />}>
          <Route path="contracts" element={<ContractsPage />} />
          <Route path="audit" element={<AuditPage />} />
        </Route>
        <Route element={<ProtectedRoute roles={["PAYROLL", "DIRECTOR"]} />}>
          <Route path="payroll" element={<PayrollPage />} />
          <Route path="reports" element={<ReportsPage />} />
          <Route path="payments" element={<PaymentsPage />} />
        </Route>
        <Route element={<ProtectedRoute roles={["EMPLOYEE"]} />}><Route path="payslips" element={<PayslipsPage />} /></Route>
        <Route path="attendance" element={<AttendancePage />} />
        <Route path="requests" element={<RequestsPage />} />
        <Route path="bank-accounts" element={<BankAccountsPage />} />
        <Route path="configuration" element={<ConfigurationPage />} />
        <Route path="settings" element={<SettingsPage />} />
        <Route path="*" element={<EmptyState title="Không tìm thấy trang" description="Đường dẫn này không tồn tại."><Link className="button button-primary" to="/">Về tổng quan</Link></EmptyState>} />
      </Route>
    </Route>
  </Routes>;
}
