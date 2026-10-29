namespace Payroll.Api.Contracts;

public class JobPositionListItem
{
    public long PositionId { get; set; }

    public string PositionCode { get; set; } = string.Empty;

    public string PositionName { get; set; } = string.Empty;
}