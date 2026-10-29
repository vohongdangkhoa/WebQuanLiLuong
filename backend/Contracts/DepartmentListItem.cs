namespace Payroll.Api.Contracts;

public class DepartmentListItem
{
    public long DepartmentId { get; set; }

    public string DepartmentCode { get; set; } = string.Empty;

    public string DepartmentName { get; set; } = string.Empty;
}

/* - DepartmentId: số định danh phòng ban.
- DepartmentCode: mã như FIN, HR, IT.
- DepartmentName: tên phòng ban hiển thị trên website.
Mỗi dòng Oracle trả về sẽ được chuyển thành một đối tượng DepartmentListItem. */