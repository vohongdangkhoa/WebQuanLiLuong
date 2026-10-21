import { Routes, Route } from "react-router";
import ProtectedRoute from "./components/ProtectedRoute.jsx";
import MainLayout from "./layouts/MainLayout.jsx";

import LoginPage from "./pages/LoginPage.jsx";
import DashboardPage from "./pages/DashboardPage.jsx";
import EmployeesPage from "./pages/EmployeesPage.jsx";
import AttendancePage from "./pages/AttendancePage.jsx";
import PayrollPage from "./pages/PayrollPage.jsx";
import RequestsPage from "./pages/RequestsPage.jsx";
import PaymentsPage from "./pages/PaymentsPage.jsx";
import PayslipsPage from "./pages/PayslipsPage.jsx";
import ReportsPage from "./pages/ReportsPage.jsx";

import "./App.css";

function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />

      <Route element={<ProtectedRoute />}>
        <Route element={<MainLayout />}>
          <Route index element={<DashboardPage />} />
          <Route path="employees" element={<EmployeesPage />} />
          <Route path="attendance" element={<AttendancePage />} />
          <Route path="payroll" element={<PayrollPage />} />
          <Route path="requests" element={<RequestsPage />} />
          <Route path="payments" element={<PaymentsPage />} />
          <Route path="payslips" element={<PayslipsPage />} />
          <Route path="reports" element={<ReportsPage />} />
        </Route>
      </Route>
    </Routes>
  );
}

export default App;
