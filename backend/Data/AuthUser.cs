using System.Text.Json.Serialization;

namespace Payroll.Api.Data;

public class AuthUser
{
    public long UserId { get; set; }

    public string Username { get; set; } = string.Empty;

    [JsonIgnore]
    public string PasswordHash { get; set; } = string.Empty;

    public bool IsActive { get; set; }

    public long SecurityVersion { get; set; }

    public List<string> Roles { get; set; } = new List<string>();
}