import { useEffect, useState } from "react";
import { createEmployee, getEmployees } from "../services/api";
import EmployeeAssignmentForm from "../components/EmployeeAssignmentForm";
const employeeStatusLabels = {
  ACTIVE: "Đang làm việc",
  INACTIVE: "Không hoạt động",
  TERMINATED: "Đã nghỉ việc",
};
function EmployeesPage() {
  const [employees, setEmployees] = useState([]);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState("");
  const [searchTerm, setSearchTerm] = useState("");
  const [statusFilter, setStatusFilter] = useState("");
  const [employeeCode, setEmployeeCode] = useState("");
  const [fullName, setFullName] = useState("");
  const [hireDate, setHireDate] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [submitError, setSubmitError] = useState("");
  const [submitMessage, setSubmitMessage] = useState("");
  const keyword = searchTerm.trim().toLowerCase();

  const filteredEmployees = employees.filter((employee) => {
    const code = employee.employeeCode.toLowerCase();
    const name = employee.fullName.toLowerCase();

    const matchesKeyword = code.includes(keyword) || name.includes(keyword);

    const matchesStatus =
      statusFilter === "" || employee.status === statusFilter;

    return matchesKeyword && matchesStatus;
  });
  useEffect(() => {
    let ignore = false;

    async function loadEmployees() {
      try {
        const data = await getEmployees();

        if (!ignore) {
          setEmployees(data);
        }
      } catch (error) {
        if (!ignore) {
          setLoadError(error.message || "Không tải được danh sách nhân viên.");
        }
      } finally {
        if (!ignore) {
          setIsLoading(false);
        }
      }
    }

    loadEmployees();

    return () => {
      ignore = true;
    };
  }, []);
  async function handleCreateEmployee(event) {
    event.preventDefault();

    if (isSubmitting) {
      return;
    }

    setIsSubmitting(true);
    setSubmitError("");
    setSubmitMessage("");

    try {
      await createEmployee({
        employeeCode: employeeCode.trim(),
        fullName: fullName.trim(),
        hireDate,
      });

      setEmployeeCode("");
      setFullName("");
      setHireDate("");

      setSearchTerm("");
      setStatusFilter("");

      setSubmitMessage("Đã thêm nhân viên.");

      try {
        const updatedEmployees = await getEmployees();
        setEmployees(updatedEmployees);
      } catch {
        setSubmitMessage(
          "Đã thêm nhân viên. Danh sách chưa cập nhật, hãy tải lại trang để xem kết quả.",
        );
      }
    } catch (error) {
      setSubmitError(
        error.message || "Không thêm được nhân viên. Vui lòng thử lại.",
      );
    } finally {
      setIsSubmitting(false);
    }
  }
  async function handleAssignmentCreated() {
    const updatedEmployees = await getEmployees();
    setEmployees(updatedEmployees);

    setSearchTerm("");
    setStatusFilter("");
  }
  if (isLoading) {
    return <p role="status">Đang tải danh sách nhân viên...</p>;
  }

  if (loadError) {
    return <p role="alert">{loadError}</p>;
  }
  return (
    <main>
      <h1>Nhân viên</h1>
      <p>Đây là nơi quản lý hồ sơ nhân viên.</p>
      <section className="employee-create">
        <h2>Thêm nhân viên</h2>

        <form onSubmit={handleCreateEmployee}>
          <fieldset disabled={isSubmitting}>
            <legend>Thông tin cơ bản</legend>

            <div>
              <label htmlFor="new-employee-code">Mã nhân viên</label>
              <input
                id="new-employee-code"
                type="text"
                maxLength={30}
                required
                value={employeeCode}
                onChange={(event) => setEmployeeCode(event.target.value)}
              />
            </div>

            <div>
              <label htmlFor="new-employee-name">Họ tên</label>
              <input
                id="new-employee-name"
                type="text"
                maxLength={150}
                required
                value={fullName}
                onChange={(event) => setFullName(event.target.value)}
              />
            </div>

            <div>
              <label htmlFor="new-employee-hire-date">Ngày vào làm</label>
              <input
                id="new-employee-hire-date"
                type="date"
                required
                value={hireDate}
                onChange={(event) => setHireDate(event.target.value)}
              />
            </div>

            <button type="submit">
              {isSubmitting ? "Đang xử lý..." : "Lưu nhân viên"}
            </button>
          </fieldset>

          {submitError && (
            <p className="employee-create-error" role="alert">
              {submitError}
            </p>
          )}

          {submitMessage && (
            <p className="employee-create-message" role="status">
              {submitMessage}
            </p>
          )}
        </form>
      </section>

      <EmployeeAssignmentForm
        employees={employees}
        onAssignmentCreated={handleAssignmentCreated}
      />

      <div className="employees-search">
        <label htmlFor="employee-search">Tìm nhân viên</label>

        <input
          id="employee-search"
          type="search"
          placeholder="Nhập mã hoặc họ tên nhân viên"
          value={searchTerm}
          onChange={(event) => setSearchTerm(event.target.value)}
        />
      </div>
      <div className="employees-status-filter">
        <label htmlFor="employee-status">Trạng thái</label>

        <select
          id="employee-status"
          value={statusFilter}
          onChange={(event) => setStatusFilter(event.target.value)}
        >
          <option value="">Tất cả trạng thái</option>

          {Object.entries(employeeStatusLabels).map(([value, label]) => (
            <option key={value} value={value}>
              {label}
            </option>
          ))}
        </select>
      </div>
      <table className="employees-table">
        <caption>Danh sách nhân viên</caption>

        <thead>
          <tr>
            <th scope="col">Mã nhân viên</th>
            <th scope="col">Họ tên</th>
            <th scope="col">Phòng ban</th>
            <th scope="col">Trạng thái</th>
          </tr>
        </thead>

        <tbody>
          {filteredEmployees.length === 0 ? (
            <tr>
              <td colSpan={4}>
                {keyword || statusFilter
                  ? "Không tìm thấy nhân viên phù hợp."
                  : "Chưa có nhân viên."}
              </td>
            </tr>
          ) : (
            filteredEmployees.map((employee) => (
              <tr key={employee.employeeId}>
                <td>{employee.employeeCode}</td>
                <td>{employee.fullName}</td>
                <td>{employee.departmentName ?? "Chưa phân công"}</td>
                <td>
                  {employeeStatusLabels[employee.status] ?? employee.status}
                </td>
              </tr>
            ))
          )}
        </tbody>
      </table>
    </main>
  );
}

export default EmployeesPage;

/* - employees: giữ danh sách nhân viên. Ban đầu là [], tức danh sách rỗng. setEmployees dùng để cập nhật danh sách.
- isLoading: cho biết đang tải dữ liệu hay không. Ban đầu là true. setIsLoading dùng để đổi trạng thái này.
- loadError: giữ thông báo lỗi. Ban đầu là chuỗi rỗng "". setLoadError dùng để cập nhật thông báo.
useState giúp React nhớ các giá trị này và cập nhật giao diện khi mình gọi các hàm set.... */

/* useEffect: bắt đầu tải dữ liệu khi trang được đưa lên giao diện.
await getEmployees(): chờ danh sách từ backend.
setEmployees(data): lưu danh sách nhận được.
catch: lưu thông báo nếu gặp lỗi.
finally: kết thúc trạng thái đang tải.
ignore: giúp bỏ qua kết quả đến muộn khi bạn đã rời trang. */

/* employees.length === 0: danh sách rỗng thì hiện “Chưa có nhân viên”.
employees.map(...): tạo một dòng <tr> cho mỗi nhân viên.
key={employee.employeeId}: giúp React nhận diện từng dòng.
?? "Chưa phân công": hiện chữ này nếu tên phòng ban nhận được là null. */

/* htmlFor và id giống nhau để nối nhãn với ô nhập.
type="search": ô nhập dành cho tìm kiếm.
value={searchTerm}: hiển thị nội dung đang lưu trong state.
onChange: mỗi lần gõ, cập nhật searchTerm bằng nội dung mới. */

/* - trim(): bỏ khoảng trắng thừa ở đầu và cuối.
- toLowerCase(): chuyển về chữ thường để tìm không phân biệt hoa/thường.
- filter(...): tạo danh sách những nhân viên khớp từ khóa.
- ||: chỉ cần mã hoặc họ tên chứa từ khóa là được chọn.
2. Trong <tbody>, đổi đúng hai chỗ:
- employees.length === 0 thành filteredEmployees.length === 0.
- employees.map thành filteredEmployees.map. */
/* 
Gõ nv002: chỉ hiện nhân viên NV002.
Gõ huy: cũng hiện nhân viên NV002.
Gõ zzz: hiện thông báo không tìm thấy.
Xóa hết nội dung: hiện lại đủ ba nhân viên. */

/* - filteredEmployees.length: kiểm tra kết quả lọc có rỗng không.
- filteredEmployees.map: vẽ các nhân viên khớp từ khóa.
2. Nhấn Ctrl + S, rồi thử lại:
- Gõ nv002: chỉ còn một dòng NV002.
- Gõ zzz: hiện thông báo không tìm thấy.
- Xóa hết chữ: hiện lại ba nhân viên. */
/* 
<select>: tạo ô chọn.
<option>: mỗi lựa chọn trong ô.
value và onChange: lưu lựa chọn vào statusFilter.
Object.entries(employeeStatusLabels): chuyển bảng tên trạng thái thành các cặp mã và nhãn, chẳng hạn ["ACTIVE", "Đang làm việc"].
.map(...): tạo một lựa chọn cho mỗi cặp đó. */

/* matchesKeyword: mã hoặc họ tên có chứa từ khóa.
matchesStatus: chọn “Tất cả” hoặc trạng thái nhân viên đúng với lựa chọn.
&&: phải thỏa mãn cả hai điều kiện mới được hiển thị. */
/* Xóa từ khóa, chọn Đang làm việc → hiện ba nhân viên.
Chọn Đã nghỉ việc → báo không tìm thấy.
Chọn Tất cả trạng thái, gõ nv002 → hiện một nhân viên.
Giữ nv002, chọn Không hoạt động → báo không tìm thấy. */
