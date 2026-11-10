using System.Data;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using Oracle.ManagedDataAccess.Client;
using Oracle.ManagedDataAccess.Types;
using Payroll.Api.Contracts;

namespace Payroll.Api.Data;

public sealed class OracleFinanceRepository(
    OracleConnectionFactory connectionFactory, IConfiguration configuration, IHostEnvironment environment)
{
    private static readonly CultureInfo Invariant = CultureInfo.InvariantCulture;
    private readonly string _documentRoot = Path.Combine(environment.ContentRootPath, ".local", "finance-documents");

    public static OracleParameter Id(string name, long? value) => new(name, OracleDbType.Int64)
        { Value = value.HasValue ? value.Value : DBNull.Value };
    private static OracleParameter Text(string name, string? value) => new(name, OracleDbType.Varchar2)
        { Value = value is null ? DBNull.Value : value };
    private static OracleParameter Number(string name, decimal value) => new(name, OracleDbType.Decimal) { Value = value };
    private static OracleParameter Day(string name, DateOnly value) => new(name, OracleDbType.Date)
        { Value = value.ToDateTime(TimeOnly.MinValue, DateTimeKind.Unspecified) };

    private static OracleCommand Command(OracleConnection connection, string procedure, long actor, params OracleParameter[] parameters)
    {
        var command = connection.CreateCommand();
        command.CommandText = procedure;
        command.CommandType = CommandType.StoredProcedure;
        command.BindByName = true;
        command.CommandTimeout = 180;
        command.Parameters.Add(Id("p_actor", actor));
        command.Parameters.AddRange(parameters);
        return command;
    }

    private static async Task ExecuteOnAsync(OracleConnection connection, string procedure, long actor,
        CancellationToken ct, params OracleParameter[] parameters)
    {
        using var command = Command(connection, procedure, actor, parameters);
        await command.ExecuteNonQueryAsync(ct);
    }

    private static async Task<long> IdOnAsync(OracleConnection connection, string procedure, long actor,
        string output, CancellationToken ct, params OracleParameter[] parameters)
    {
        using var command = Command(connection, procedure, actor, parameters);
        var result = command.Parameters.Add(output, OracleDbType.Decimal);
        result.Direction = ParameterDirection.Output;
        await command.ExecuteNonQueryAsync(ct);
        if (result.Value is not OracleDecimal id || id.IsNull || !id.IsInt || !id.IsPositive)
            throw new FinancePortalException(500, "Oracle trả mã định danh không hợp lệ; giao dịch chưa được xác nhận.");
        return checked((long)id.Value);
    }

    private async Task<T> TransactionAsync<T>(Func<OracleConnection, Task<T>> action, CancellationToken ct)
    {
        using var connection = connectionFactory.CreateConnection();
        await connection.OpenAsync(ct);
        using var transaction = connection.BeginTransaction();
        var result = await action(connection);
        transaction.Commit();
        return result;
    }

    private static string Camel(string name)
    {
        var words = name.ToLowerInvariant().Split('_');
        return words[0] + string.Concat(words.Skip(1).Select(word => char.ToUpperInvariant(word[0]) + word[1..]));
    }

    private static object? JsonValue(object value) => value switch
    {
        DBNull => null,
        OracleDecimal number => number.IsNull ? null : number.Value,
        DateTime date => date.TimeOfDay == TimeSpan.Zero ? date.ToString("yyyy-MM-dd", Invariant) : date.ToString("yyyy-MM-ddTHH:mm:ss", Invariant),
        DateTimeOffset date => date.ToString("O", Invariant),
        OracleTimeStampTZ date => date.IsNull ? null : DateTime.SpecifyKind(
            date.ToUniversalTime().Value, DateTimeKind.Utc).ToString("O", Invariant),
        OracleTimeStamp date => date.IsNull ? null : date.Value.ToString("yyyy-MM-ddTHH:mm:ss", Invariant),
        OracleDate date => date.IsNull ? null : date.Value.ToString("yyyy-MM-dd", Invariant),
        OracleString text => text.IsNull ? null : text.Value,
        _ => value
    };

    private static async Task<List<Dictionary<string, object?>>> ReadOnAsync(OracleConnection connection,
        string procedure, long actor, CancellationToken ct, params OracleParameter[] parameters)
    {
        using var command = Command(connection, procedure, actor, parameters);
        command.Parameters.Add("p_rows", OracleDbType.RefCursor).Direction = ParameterDirection.Output;
        using var reader = await command.ExecuteReaderAsync(ct);
        var rows = new List<Dictionary<string, object?>>();
        while (await reader.ReadAsync(ct))
        {
            var row = new Dictionary<string, object?>();
            for (var i = 0; i < reader.FieldCount; i++)
            {
                var value = reader.GetProviderSpecificValue(i) is OracleTimeStampTZ timestamp
                    ? timestamp : reader.GetValue(i);
                row[Camel(reader.GetName(i))] = JsonValue(value);
            }
            if (procedure.EndsWith("list_errors", StringComparison.Ordinal) && row.TryGetValue("errorCode", out var code))
                row["errorMessage"] = FinanceErrors.Describe(Math.Abs(Convert.ToInt32(code, Invariant))).Message;
            rows.Add(row);
        }
        return rows;
    }

    public async Task<List<Dictionary<string, object?>>> ReadAsync(string procedure, long actor,
        CancellationToken ct, params OracleParameter[] parameters)
    {
        using var connection = connectionFactory.CreateConnection();
        await connection.OpenAsync(ct);
        return await ReadOnAsync(connection, procedure, actor, ct, parameters);
    }

    public Task<long> CreatePeriodAsync(long actor, DateOnly start, CancellationToken ct) =>
        TransactionAsync(c => IdOnAsync(c, "PAYROLL_APP.PKG_FINANCE_PORTAL.create_period", actor, "p_period", ct, Day("p_start", start)), ct);

    public Task<long> CalculateAsync(long actor, long period, string key, CancellationToken ct) =>
        TransactionAsync(c => IdOnAsync(c, "PAYROLL_APP.PKG_PAYROLL_CORE.calculate", actor, "p_run", ct,
            Id("p_period", period), Text("p_request_key", key)), ct);

    public Task<long> RecalculateAsync(long actor, long run, string key, CancellationToken ct) =>
        TransactionAsync(async c =>
        {
            var period = await IdOnAsync(c, "PAYROLL_APP.PKG_FINANCE_PORTAL.run_period", actor, "p_period", ct, Id("p_run", run));
            return await IdOnAsync(c, "PAYROLL_APP.PKG_PAYROLL_CORE.calculate", actor, "p_run", ct,
                Id("p_period", period), Text("p_request_key", key));
        }, ct);

    public Task<long> CreateBatchAsync(long actor, long run, string key, CancellationToken ct) =>
        TransactionAsync(c => IdOnAsync(c, "PAYROLL_APP.PKG_PAYMENT.create_batch", actor, "p_batch", ct,
            Id("p_run", run), Text("p_request_key", key)), ct);

    public Task<bool> WithdrawAsync(long actor, long run, string reason, CancellationToken ct) =>
        WriteAsync("PAYROLL_APP.PKG_FINANCE_PORTAL.withdraw_run", actor, ct, Id("p_run", run), Text("p_reason", reason));

    public Task<bool> WriteAsync(string procedure, long actor, CancellationToken ct, params OracleParameter[] parameters) =>
        TransactionAsync(async c => { await ExecuteOnAsync(c, procedure, actor, ct, parameters); return true; }, ct);

    public Task<bool> DecideAsync(long actor, long run, string decision, string? reason, CancellationToken ct) =>
        WriteAsync("PAYROLL_APP.PKG_PAYROLL_CORE.decide_run", actor, ct, Id("p_run", run),
            Text("p_decision", decision), Text("p_reason", reason));

    private byte[] BankKey()
    {
        try
        {
            var key = Convert.FromBase64String(configuration["BankEncryptionKey"] ?? "");
            if (key.Length == 32) return key;
            CryptographicOperations.ZeroMemory(key);
        }
        catch (FormatException) { }
        throw new FinancePortalException(503, "Chưa cấu hình khóa mã hóa ngân hàng hợp lệ trên máy chủ; chưa xuất hoặc xác nhận thanh toán.");
    }

    private async Task StoreDocumentAsync(string hash, byte[] content, byte[] key, CancellationToken ct)
    {
        Directory.CreateDirectory(_documentRoot);
        var destination = Path.Combine(_documentRoot, hash + ".enc");
        var temporary = Path.Combine(_documentRoot, Guid.NewGuid().ToString("N") + ".tmp");
        try
        {
            await File.WriteAllTextAsync(temporary, FinanceEvidence.Encrypt(content, key), new UTF8Encoding(false), ct);
            File.Move(temporary, destination, true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }

    private static string CsvCell(object? value) => FinanceEvidence.CsvCell(value);
    public static byte[] Csv(IEnumerable<Dictionary<string, object?>> rows) => FinanceEvidence.Csv(rows);

    public Task<FinanceDownload> ExportAsync(long actor, long batch, CancellationToken ct) => TransactionAsync(async connection =>
    {
        var key = BankKey();
        try
        {
            var rows = await ReadOnAsync(connection, "PAYROLL_APP.PKG_PAYMENT.export_rows", actor, ct, Id("p_batch", batch));
            if (rows.Count == 0) throw new FinancePortalException(409, "Đợt thanh toán không có chỉ dẫn chuyển khoản.");
            var output = new StringBuilder("\uFEFFtransferReference,bankCode,accountNumber,holderName,amount\r\n");
            foreach (var row in rows)
            {
                var account = Encoding.UTF8.GetString(FinanceEvidence.Decrypt(Convert.ToString(row["accountCiphertextSnapshot"], Invariant) ?? "", key));
                if (account.Length == 0 || account.Length > 100 || !account.All(char.IsAsciiDigit))
                    throw new FinancePortalException(409, "Số tài khoản sau giải mã không hợp lệ; chưa đánh dấu xuất tệp.");
                output.Append(string.Join(',', new[] {
                    CsvCell(row["transferReference"]), CsvCell(row["bankCodeSnapshot"]), CsvCell(account),
                    CsvCell(row["holderNameSnapshot"]), Convert.ToDecimal(row["amount"], Invariant).ToString("0.00", Invariant)
                })).Append("\r\n");
            }
            var bytes = Encoding.UTF8.GetBytes(output.ToString());
            var hash = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
            var batches = await ReadOnAsync(connection, "PAYROLL_APP.PKG_FINANCE_PORTAL.list_batches", actor, ct, Id("p_run", null));
            var current = batches.SingleOrDefault(b => Convert.ToInt64(b["batchId"], Invariant) == batch)
                ?? throw new FinancePortalException(404, "Không tìm thấy đợt thanh toán.");
            var documentId = current["exportDocumentId"] is null ? (long?)null : Convert.ToInt64(current["exportDocumentId"], Invariant);
            if (documentId.HasValue && !string.Equals(Convert.ToString(current["exportSha256"], Invariant)?.Trim(), hash, StringComparison.OrdinalIgnoreCase))
                throw new FinancePortalException(409, "Tệp tái xuất khác hash chứng từ đã xuất; dừng để kiểm tra.");
            await StoreDocumentAsync(hash, bytes, key, ct);
            if (!documentId.HasValue)
                documentId = await RegisterDocumentAsync(connection, actor, $"payment-{batch}.csv", hash, bytes.Length, ct);
            await ExecuteOnAsync(connection, "PAYROLL_APP.PKG_PAYMENT.mark_exported", actor, ct,
                Id("p_batch", batch), Id("p_document", documentId), Text("p_sha256", hash));
            return new FinanceDownload(bytes, $"payment-{batch}.csv");
        }
        finally { CryptographicOperations.ZeroMemory(key); }
    }, ct);

    private static Task<long> RegisterDocumentAsync(OracleConnection connection, long actor, string name, string hash, int size, CancellationToken ct) =>
        IdOnAsync(connection, "PAYROLL_APP.PKG_REQUESTS.register_document", actor, "p_document", ct,
            Text("p_storage_key", $"finance/{hash}.enc"), Text("p_name", Path.GetFileName(name)), Text("p_mime", "text/csv"),
            Number("p_size", size), Text("p_hash", hash));

    public async Task<(long ImportId, int LineCount)> ReconcileAsync(long actor, long batch, ImportReconciliationRequest request, CancellationToken ct)
    {
        var fileName = Path.GetFileName(request.FileName).Trim();
        if (string.IsNullOrWhiteSpace(fileName) || fileName.Any(char.IsControl))
            throw new FinancePortalException(400, "Tên tệp đối soát không hợp lệ.");
        var rows = FinanceEvidence.ParseReconciliation(request.Content);
        var bytes = Encoding.UTF8.GetBytes(request.Content);
        var hash = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
        return await TransactionAsync(async connection =>
        {
            await ExecuteOnAsync(connection, "PAYROLL_APP.PKG_FINANCE_PORTAL.recon_context", actor, ct,
                Id("p_batch", batch), Text("p_hash", hash));
            var items = await ReadOnAsync(connection, "PAYROLL_APP.PKG_FINANCE_PORTAL.list_payment_items", actor, ct, Id("p_batch", batch));
            var references = items.Select(x => Convert.ToString(x["transferReference"], Invariant) ?? "").ToHashSet(StringComparer.Ordinal);
            if (rows.Any(row => !references.Contains(row.Reference)))
                throw new FinancePortalException(400, "Tệp chứa tham chiếu không thuộc đợt thanh toán đang chọn.");
            var key = BankKey();
            try { await StoreDocumentAsync(hash, bytes, key, ct); }
            finally { CryptographicOperations.ZeroMemory(key); }
            var document = await RegisterDocumentAsync(connection, actor, fileName, hash, bytes.Length, ct);
            var import = await IdOnAsync(connection, "PAYROLL_APP.PKG_REQUESTS.register_recon", actor, "p_import", ct,
                Id("p_document", document), Text("p_hash", hash));
            foreach (var row in rows)
            {
                var line = await IdOnAsync(connection, "PAYROLL_APP.PKG_REQUESTS.add_recon_line", actor, "p_id", ct,
                    Id("p_import", import), Number("p_line", row.Line), Text("p_ref", row.Reference), Number("p_amount", row.Amount),
                    Text("p_status", row.Status), Text("p_bank_tx", row.Transaction), Text("p_reason", row.Reason));
                await ExecuteOnAsync(connection, "PAYROLL_APP.PKG_PAYMENT.apply_recon_line", actor, ct, Id("p_line", line));
            }
            return (import, rows.Count);
        }, ct);
    }
}

