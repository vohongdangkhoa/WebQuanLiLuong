namespace Payroll.Api.Contracts;

public class EmployeeListItem
{
    public long EmployeeId { get; set; }

    public string EmployeeCode { get; set; } = string.Empty;

    public string FullName { get; set; } = string.Empty;

    public string? DepartmentName { get; set; }

    public string Status { get; set; } = string.Empty;
}

/* Mỗi đối tượng EmployeeListItem sẽ chứa thông tin của một dòng nhân viên:
- EmployeeId: số định danh nội bộ.
- EmployeeCode: mã nhân viên, chẳng hạn NV001.
- FullName: họ tên.
- DepartmentName: tên phòng ban.
- Status: trạng thái, chẳng hạn ACTIVE.
Hai chi tiết cần hiểu:
- string.Empty là chuỗi rỗng "", dùng làm giá trị ban đầu.
- Dấu ? trong string? cho phép DepartmentName nhận null, vì nhân viên có thể chưa có phân công phòng ban đang hiệu lực. */