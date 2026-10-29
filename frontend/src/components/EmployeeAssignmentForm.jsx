import { useEffect, useState } from "react";
import { getDepartments, getJobPositions } from "../services/api";

function EmployeeAssignmentForm({ employees }) {
  const [employeeId, setEmployeeId] = useState("");
  const [departments, setDepartments] = useState([]);
  const [departmentId, setDepartmentId] = useState("");
  const [jobPositions, setJobPositions] = useState([]);
  const [positionId, setPositionId] = useState("");
  const [validFrom, setValidFrom] = useState("");
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState("");

  useEffect(() => {
    let ignore = false;

    async function loadCatalogs() {
      try {
        const [departmentData, jobPositionData] = await Promise.all([
          getDepartments(),
          getJobPositions(),
        ]);

        if (!ignore) {
          setDepartments(departmentData);
          setJobPositions(jobPositionData);
        }
      } catch (error) {
        if (!ignore) {
          setLoadError(error.message || "Không tải được danh mục phân công.");
        }
      } finally {
        if (!ignore) {
          setIsLoading(false);
        }
      }
    }

    loadCatalogs();

    return () => {
      ignore = true;
    };
  }, []);

  if (isLoading) {
    return <p role="status">Đang tải danh mục phân công...</p>;
  }

  if (loadError) {
    return <p role="alert">{loadError}</p>;
  }

  return (
    <section className="employee-assignment">
      <h2>Phân công phòng ban</h2>
      <div>
        <label htmlFor="assignment-employee">Nhân viên</label>

        <select
          id="assignment-employee"
          value={employeeId}
          onChange={(event) => setEmployeeId(event.target.value)}
          disabled={employees.length === 0}
        >
          <option value="">
            {employees.length === 0
              ? "Chưa có nhân viên"
              : "-- Chọn nhân viên --"}
          </option>

          {employees.map((employee) => (
            <option key={employee.employeeId} value={employee.employeeId}>
              {employee.employeeCode} — {employee.fullName}
            </option>
          ))}
        </select>
      </div>
      <label htmlFor="assignment-department">Phòng ban</label>
      <select
        id="assignment-department"
        value={departmentId}
        onChange={(event) => setDepartmentId(event.target.value)}
        disabled={departments.length === 0}
      >
        <option value="">
          {departments.length === 0
            ? "Chưa có phòng ban đang hoạt động"
            : "-- Chọn phòng ban --"}
        </option>

        {departments.map((department) => (
          <option key={department.departmentId} value={department.departmentId}>
            {department.departmentName}
          </option>
        ))}
      </select>
      <div>
        <label htmlFor="assignment-position">Chức danh</label>

        <select
          id="assignment-position"
          value={positionId}
          onChange={(event) => setPositionId(event.target.value)}
          disabled={jobPositions.length === 0}
        >
          <option value="">
            {jobPositions.length === 0
              ? "Chưa có chức danh đang hoạt động"
              : "-- Chọn chức danh --"}
          </option>

          {jobPositions.map((jobPosition) => (
            <option key={jobPosition.positionId} value={jobPosition.positionId}>
              {jobPosition.positionName}
            </option>
          ))}
        </select>
      </div>

      <div>
        <label htmlFor="assignment-valid-from">Ngày bắt đầu phân công</label>

        <input
          id="assignment-valid-from"
          type="date"
          value={validFrom}
          onChange={(event) => setValidFrom(event.target.value)}
        />
      </div>
    </section>
  );
}

export default EmployeeAssignmentForm;
