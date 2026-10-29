using System.Data;
using Oracle.ManagedDataAccess.Types;
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
    public async Task<long> CreateEmployeeAsync(
    long actorId,
    CreateEmployeeRequest request,
    CancellationToken cancellationToken)
{
    if (request.HireDate is not DateOnly hireDate)
    {
        throw new ArgumentException(
            "Ngày vào làm là bắt buộc.",
            nameof(request));
    }

    using var connection = _connectionFactory.CreateConnection();
    await connection.OpenAsync(cancellationToken);

    using var transaction = connection.BeginTransaction();

    using var command = connection.CreateCommand();
    command.CommandText = "PAYROLL_APP.PKG_HR_WRITE.create_employee";
    command.CommandType = CommandType.StoredProcedure;
    command.BindByName = true;

    command.Parameters.Add("p_actor", OracleDbType.Int64)
        .Value = actorId;

    command.Parameters.Add("p_employee_code", OracleDbType.Varchar2)
        .Value = request.EmployeeCode;

    command.Parameters.Add("p_full_name", OracleDbType.Varchar2)
        .Value = request.FullName;

    command.Parameters.Add("p_hire_date", OracleDbType.Date)
        .Value = hireDate.ToDateTime(
            TimeOnly.MinValue,
            DateTimeKind.Unspecified);

    var employeeIdParameter = command.Parameters.Add(
        "p_employee_id", OracleDbType.Decimal);
    employeeIdParameter.Direction = ParameterDirection.Output;

    await command.ExecuteNonQueryAsync(cancellationToken);

    var oracleId = (OracleDecimal)employeeIdParameter.Value;

    if (oracleId.IsNull || !oracleId.IsInt || !oracleId.IsPositive)
    {
        throw new InvalidOperationException(
            "Oracle trả về mã định danh nhân viên không hợp lệ.");
    }

    var employeeId = checked((long)oracleId.Value);

    transaction.Commit();

    return employeeId;
}
public async Task<long> CreateAssignmentAsync(
    long actorId,
    long employeeId,
    CreateEmployeeAssignmentRequest request,
    CancellationToken cancellationToken)
{
    if (request.ValidFrom is not DateOnly validFrom)
    {
        throw new ArgumentException(
            "Ngày bắt đầu phân công là bắt buộc.",
            nameof(request));
    }

    using var connection = _connectionFactory.CreateConnection();
    await connection.OpenAsync(cancellationToken);

    using var transaction = connection.BeginTransaction();

    using var command = connection.CreateCommand();
    command.CommandText = "PAYROLL_APP.PKG_HR_WRITE.create_assignment";
    command.CommandType = CommandType.StoredProcedure;
    command.BindByName = true;

    command.Parameters.Add("p_actor", OracleDbType.Int64)
        .Value = actorId;

    command.Parameters.Add("p_employee_id", OracleDbType.Int64)
        .Value = employeeId;

    command.Parameters.Add("p_department_id", OracleDbType.Int64)
        .Value = request.DepartmentId;

    command.Parameters.Add("p_position_id", OracleDbType.Int64)
        .Value = request.PositionId;

    command.Parameters.Add("p_valid_from", OracleDbType.Date)
        .Value = validFrom.ToDateTime(
            TimeOnly.MinValue,
            DateTimeKind.Unspecified);

    var assignmentIdParameter = command.Parameters.Add(
        "p_assignment_id", OracleDbType.Decimal);
    assignmentIdParameter.Direction = ParameterDirection.Output;

    await command.ExecuteNonQueryAsync(cancellationToken);

    var oracleId = (OracleDecimal)assignmentIdParameter.Value;

    if (oracleId.IsNull || !oracleId.IsInt || !oracleId.IsPositive)
    {
        throw new InvalidOperationException(
            "Oracle trả về mã định danh phân công không hợp lệ.");
    }

    var assignmentId = checked((long)oracleId.Value);

    transaction.Commit();

    return assignmentId;
}
}

/* OracleEmployeeRepository: nơi mình sẽ viết phần gọi Oracle để đọc nhân viên.
_connectionFactory: giữ công cụ tạo kết nối Oracle mà mình đã xây dựng trước đó.
OracleEmployeeRepository(...): hàm khởi tạo, chạy khi tạo một đối tượng của lớp này. Nó nhận công cụ tạo kết nối rồi lưu vào _connectionFactory.
private readonly: biến này dùng bên trong lớp và được gán khi khởi tạo. */
/* Kiểm tra đã có ngày vào làm.
Mở kết nối và bắt đầu giao dịch bằng BeginTransaction().
Truyền năm tham số, khớp với thủ tục Oracle vừa tạo. p_employee_id có hướng Output vì Oracle trả ID về cho mình.
Chuyển ngày vào làm thành giá trị ngày lúc 00:00:00 để gửi Oracle.
Gọi thủ tục bằng ExecuteNonQueryAsync().
Kiểm tra ID nhận về: có giá trị, là số nguyên và lớn hơn 0. Đây là ý nghĩa của IsNull, IsInt, IsPositive. Tài liệu Oracle
checked kiểm tra ID có nằm trong giới hạn kiểu long; sau đó Commit() xác nhận lưu và return trả ID. */