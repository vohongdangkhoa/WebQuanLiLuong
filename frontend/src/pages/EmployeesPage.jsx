function EmployeesPage() {
  return (
    <main>
      <h1>Nhân viên</h1>
      <p>Đây là nơi quản lý hồ sơ nhân viên.</p>
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
          <tr>
            <td colSpan={4}>Chưa tải danh sách nhân viên.</td>
          </tr>
        </tbody>
      </table>
    </main>
  );
}

export default EmployeesPage;
