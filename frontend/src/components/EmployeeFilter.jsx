import useAuth from "../hooks/useAuth";
import { hasRole } from "../utils/format";
import { Alert, Icon, ResourceState, SelectField } from "./ui";

export function EmployeeIdentity({ employee }) {
  return <div className="field employee-identity">
    <span>Nhân viên</span>
    <div className="employee-identity-value">
      <Icon name="employees" size={20} />
      <div><strong>{employee.fullName}</strong><small>{employee.employeeCode}</small></div>
    </div>
  </div>;
}

export default function EmployeeFilter({ resource, value, onChange }) {
  const { user } = useAuth();
  const manager = hasRole(user, "HR", "PAYROLL", "DIRECTOR");
  const employees = resource.data?.employees || [];

  return <ResourceState resource={resource}>
    {manager ? <SelectField label="Nhân viên" value={value} onChange={onChange}
      options={employees.map((employee) => ({
        value: employee.employeeId,
        label: `${employee.employeeCode} · ${employee.fullName}`,
      }))}
      placeholder="Tất cả nhân viên được xem" />
      : employees.length === 1 ? <EmployeeIdentity employee={employees[0]} />
        : resource.data && <Alert>Chưa xác định được hồ sơ cá nhân. Vui lòng liên hệ bộ phận nhân sự để kiểm tra tài khoản.</Alert>}
  </ResourceState>;
}
