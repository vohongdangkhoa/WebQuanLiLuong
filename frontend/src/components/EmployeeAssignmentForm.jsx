import { useEffect, useState } from "react";
import {
  createEmployeeAssignment,
  getDepartments,
  getJobPositions,
} from "../services/api";

function EmployeeAssignmentForm({ employees, onAssignmentCreated }) {
  const [employeeId, setEmployeeId] = useState("");
  const [departments, setDepartments] = useState([]);
  const [departmentId, setDepartmentId] = useState("");
  const [jobPositions, setJobPositions] = useState([]);
  const [positionId, setPositionId] = useState("");
  const [validFrom, setValidFrom] = useState("");
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [submitError, setSubmitError] = useState("");
  const [submitMessage, setSubmitMessage] = useState("");

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
  async function handleSubmit(event) {
    event.preventDefault();

    if (isSubmitting) {
      return;
    }

    setSubmitError("");
    setSubmitMessage("");

    if (!employeeId || !departmentId || !positionId || !validFrom) {
      setSubmitError(
        "Vui lòng chọn đầy đủ nhân viên, phòng ban, chức danh và ngày bắt đầu.",
      );
      return;
    }

    setIsSubmitting(true);

    try {
      await createEmployeeAssignment(Number(employeeId), {
        departmentId: Number(departmentId),
        positionId: Number(positionId),
        validFrom,
      });

      setEmployeeId("");
      setDepartmentId("");
      setPositionId("");
      setValidFrom("");
      setSubmitMessage("Đã phân công nhân viên.");

      try {
        await onAssignmentCreated();
      } catch {
        setSubmitMessage(
          "Đã phân công nhân viên. Danh sách chưa cập nhật, hãy tải lại trang để xem kết quả.",
        );
      }
    } catch (error) {
      setSubmitError(
        error.message || "Không lưu được phân công. Vui lòng thử lại.",
      );
    } finally {
      setIsSubmitting(false);
    }
  }
  if (isLoading) {
    return <p role="status">Đang tải danh mục phân công...</p>;
  }

  if (loadError) {
    return <p role="alert">{loadError}</p>;
  }

  return (
    <section className="employee-assignment">
      <h2>Phân công phòng ban</h2>
      <form onSubmit={handleSubmit}>
        <fieldset disabled={isSubmitting}>
          <legend>Thông tin phân công</legend>
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
              <option
                key={department.departmentId}
                value={department.departmentId}
              >
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
                <option
                  key={jobPosition.positionId}
                  value={jobPosition.positionId}
                >
                  {jobPosition.positionName}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label htmlFor="assignment-valid-from">
              Ngày bắt đầu phân công
            </label>

            <input
              id="assignment-valid-from"
              type="date"
              value={validFrom}
              onChange={(event) => setValidFrom(event.target.value)}
            />
          </div>

          <button
            type="submit"
            disabled={
              isSubmitting ||
              employees.length === 0 ||
              departments.length === 0 ||
              jobPositions.length === 0
            }
          >
            {isSubmitting ? "Đang lưu..." : "Lưu phân công"}
          </button>
        </fieldset>

        {submitError && (
          <p className="employee-assignment-error" role="alert">
            {submitError}
          </p>
        )}

        {submitMessage && (
          <p className="employee-assignment-message" role="status">
            {submitMessage}
          </p>
        )}
      </form>
    </section>
  );
}

export default EmployeeAssignmentForm;
