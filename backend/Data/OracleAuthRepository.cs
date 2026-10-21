namespace Payroll.Api.Data;
using System.Data;
using Oracle.ManagedDataAccess.Client;
using Oracle.ManagedDataAccess.Types;

public class OracleAuthRepository
{
    private readonly OracleConnectionFactory _connectionFactory;

    public OracleAuthRepository(
        OracleConnectionFactory connectionFactory)
    {
        _connectionFactory = connectionFactory;
    }
    public async Task<AuthUser?> FindForLoginAsync(
    string username,
    CancellationToken cancellationToken = default)
{
    using var connection = _connectionFactory.CreateConnection();
    await connection.OpenAsync(cancellationToken);

    using var command = connection.CreateCommand();
    command.CommandText = "PAYROLL_APP.PKG_AUTH.find_for_login";
    command.CommandType = CommandType.StoredProcedure;
    command.BindByName = true;

    command.Parameters.Add("p_username", OracleDbType.Varchar2)
        .Value = username;

    command.Parameters.Add("p_rows", OracleDbType.RefCursor)
        .Direction = ParameterDirection.Output;

    using var reader = await command.ExecuteReaderAsync(cancellationToken);

    AuthUser? user = null;
    var roleIndex = reader.GetOrdinal("ROLE_CODE");

    while (await reader.ReadAsync(cancellationToken))
    {
        if (user is null)
        {
            user = new AuthUser
            {
                UserId = reader.GetInt64(reader.GetOrdinal("USER_ID")),
                Username = reader.GetString(reader.GetOrdinal("USERNAME")),
                PasswordHash = reader.GetString(reader.GetOrdinal("PASSWORD_HASH")),
                IsActive = reader.GetString(reader.GetOrdinal("IS_ACTIVE")) == "Y",
                SecurityVersion = reader.GetInt64(reader.GetOrdinal("SECURITY_VERSION"))
            };
        }

        if (!reader.IsDBNull(roleIndex))
        {
            user.Roles.Add(reader.GetString(roleIndex));
        }
    }

    return user;
}
public async Task<AuthUser?> FindForSessionAsync(
    long userId,
    CancellationToken cancellationToken = default)
{
    using var connection = _connectionFactory.CreateConnection();
    await connection.OpenAsync(cancellationToken);

    using var command = connection.CreateCommand();
    command.CommandText = "PAYROLL_APP.PKG_AUTH.find_for_session";
    command.CommandType = CommandType.StoredProcedure;
    command.BindByName = true;

    command.Parameters.Add("p_user_id", OracleDbType.Int64)
        .Value = userId;

    command.Parameters.Add("p_rows", OracleDbType.RefCursor)
        .Direction = ParameterDirection.Output;

    using var reader = await command.ExecuteReaderAsync(cancellationToken);

    AuthUser? user = null;
    var roleIndex = reader.GetOrdinal("ROLE_CODE");

    while (await reader.ReadAsync(cancellationToken))
    {
        if (user is null)
        {
            user = new AuthUser
            {
                UserId = reader.GetInt64(reader.GetOrdinal("USER_ID")),
                Username = reader.GetString(reader.GetOrdinal("USERNAME")),
                IsActive = reader.GetString(reader.GetOrdinal("IS_ACTIVE")) == "Y",
                SecurityVersion = reader.GetInt64(reader.GetOrdinal("SECURITY_VERSION"))
            };
        }

        if (!reader.IsDBNull(roleIndex))
        {
            user.Roles.Add(reader.GetString(roleIndex));
        }
    }

    return user;
}
/* hàm lưu hash mới. Sau này, C# sẽ gọi hàm này khi đã xác minh mật khẩu đúng và cần nâng cấp cách băm.*/
public async Task<bool> TryRehashPasswordAsync(
    AuthUser user,
    string newHash,
    CancellationToken cancellationToken = default)
{
    using var connection = _connectionFactory.CreateConnection();
    await connection.OpenAsync(cancellationToken);

    using var transaction = connection.BeginTransaction();

    using var command = connection.CreateCommand();
    command.CommandText = "PAYROLL_APP.PKG_AUTH.rehash_password";
    command.CommandType = CommandType.StoredProcedure;
    command.BindByName = true;

    command.Parameters.Add("p_user_id", OracleDbType.Int64)
        .Value = user.UserId;

    command.Parameters.Add("p_old_hash", OracleDbType.Varchar2)
        .Value = user.PasswordHash;

    command.Parameters.Add(
        "p_expected_security_version", OracleDbType.Int64)
        .Value = user.SecurityVersion;

    command.Parameters.Add("p_new_hash", OracleDbType.Varchar2)
        .Value = newHash;

    var updatedParameter = command.Parameters.Add(
        "p_updated", OracleDbType.Decimal);
    updatedParameter.Direction = ParameterDirection.Output;

    await command.ExecuteNonQueryAsync(cancellationToken);

    var updated = (OracleDecimal)updatedParameter.Value;

    if (updated.IsNull ||
        (updated.Value != 0m && updated.Value != 1m))
    {
        throw new InvalidOperationException(
            "Oracle trả về kết quả cập nhật hash không hợp lệ.");
    }

    transaction.Commit();

    return updated.Value == 1m;
}
}