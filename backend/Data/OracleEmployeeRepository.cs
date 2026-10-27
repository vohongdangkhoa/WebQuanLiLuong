using System.Data;
using Oracle.ManagedDataAccess.Client;
using Payroll.Api.Contracts;
namespace Payroll.Api.Data;

public class OracleEmployeeRepository
{
    public async Task<List<EmployeeListItem>> GetEmployeesAsync(
    long actorId,
    CancellationToken cancellationToken)
{
    using var connection = _connectionFactory.CreateConnection();
    await connection.OpenAsync(cancellationToken);

    using var command = connection.CreateCommand();
    command.CommandText = "PAYROLL_APP.PKG_HR_READ.list_employees";
    command.CommandType = CommandType.StoredProcedure;
    command.BindByName = true;

    command.Parameters.Add("p_actor", OracleDbType.Int64)
        .Value = actorId;

    command.Parameters.Add("p_rows", OracleDbType.RefCursor)
        .Direction = ParameterDirection.Output;

    using var reader = await command.ExecuteReaderAsync(cancellationToken);

    var employees = new List<EmployeeListItem>();
    var departmentIndex = reader.GetOrdinal("DEPARTMENT_NAME");

    while (await reader.ReadAsync(cancellationToken))
    {
        employees.Add(new EmployeeListItem
        {
            EmployeeId = reader.GetInt64(reader.GetOrdinal("EMPLOYEE_ID")),
            EmployeeCode = reader.GetString(reader.GetOrdinal("EMPLOYEE_CODE")),
            FullName = reader.GetString(reader.GetOrdinal("FULL_NAME")),
            DepartmentName = reader.IsDBNull(departmentIndex)
                ? null
                : reader.GetString(departmentIndex),
            Status = reader.GetString(reader.GetOrdinal("STATUS"))
        });
    }

    return employees;
}

/* - Mở kết nối Oracle.
- Gọi thủ tục list_employees, truyền mã tài khoản qua p_actor. BindByName giúp ghép tham số theo tên.
- Đọc từng dòng bằng ReadAsync, chuyển thành một EmployeeListItem rồi thêm vào danh sách.
- Trả danh sách qua return employees.
IsDBNull kiểm tra phòng ban có bị trống trong kết quả Oracle không. Các dòng using var giúp giải phóng tài nguyên khi kết thúc hàm. */


    private readonly OracleConnectionFactory _connectionFactory;

    public OracleEmployeeRepository(
        OracleConnectionFactory connectionFactory)
    {
        _connectionFactory = connectionFactory;
    }
}

/* OracleEmployeeRepository: nơi mình sẽ viết phần gọi Oracle để đọc nhân viên.
_connectionFactory: giữ công cụ tạo kết nối Oracle mà mình đã xây dựng trước đó.
OracleEmployeeRepository(...): hàm khởi tạo, chạy khi tạo một đối tượng của lớp này. Nó nhận công cụ tạo kết nối rồi lưu vào _connectionFactory.
private readonly: biến này dùng bên trong lớp và được gán khi khởi tạo. */