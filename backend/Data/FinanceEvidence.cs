using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using Payroll.Api.Contracts;

namespace Payroll.Api.Data;

internal static class FinanceEvidence
{
    private static readonly CultureInfo Invariant = CultureInfo.InvariantCulture;
    public static string Encrypt(byte[] data, byte[] key)
    {
        var nonce = RandomNumberGenerator.GetBytes(12);
        var cipher = new byte[data.Length];
        var tag = new byte[16];
        using var aes = new AesGcm(key, 16);
        aes.Encrypt(nonce, data, cipher, tag);
        return $"v1:{Convert.ToBase64String(nonce)}:{Convert.ToBase64String(cipher)}:{Convert.ToBase64String(tag)}";
    }

    public static byte[] Decrypt(string envelope, byte[] key)
    {
        try
        {
            var parts = envelope.Split(':');
            if (parts.Length != 4 || parts[0] != "v1") throw new FormatException();
            var nonce = Convert.FromBase64String(parts[1]);
            var cipher = Convert.FromBase64String(parts[2]);
            var tag = Convert.FromBase64String(parts[3]);
            if (nonce.Length != 12 || tag.Length != 16) throw new FormatException();
            var result = new byte[cipher.Length];
            using var aes = new AesGcm(key, 16);
            aes.Decrypt(nonce, cipher, tag, result);
            return result;
        }
        catch (Exception ex) when (ex is FormatException or CryptographicException or ArgumentException)
        {
            throw new FinancePortalException(409, "Không giải mã được dữ liệu ngân hàng. Cần tài khoản đã xác minh được mã hóa bằng khóa máy chủ hiện tại; dữ liệu demo chưa đủ để xuất.");
        }
    }

    public static string CsvCell(object? value)
    {
        var text = Convert.ToString(value, Invariant) ?? "";
        if (text.Length > 0 && "=+-@\t\r".Contains(text[0])) text = "'" + text;
        return "\"" + text.Replace("\"", "\"\"") + "\"";
    }

    public static byte[] Csv(IEnumerable<Dictionary<string, object?>> rows)
    {
        var list = rows.ToList();
        if (list.Count == 0) return Encoding.UTF8.GetBytes("\uFEFFKhông có dữ liệu\r\n");
        var headers = list[0].Keys.ToArray();
        var text = new StringBuilder("\uFEFF").AppendLine(string.Join(',', headers.Select(CsvCell)));
        foreach (var row in list) text.AppendLine(string.Join(',', headers.Select(h => CsvCell(row.GetValueOrDefault(h)))));
        return Encoding.UTF8.GetBytes(text.ToString());
    }

    public sealed record ReconRow(int Line, string Reference, decimal Amount, string Status, string? Transaction, string? Reason);

    // CSV parsing is deterministic, preserves quoted commas/newlines, and rejects malformed evidence.
    public static List<ReconRow> ParseReconciliation(string content)
    {
        var records = new List<List<string>>();
        var record = new List<string>();
        var field = new StringBuilder();
        var quoted = false;
        var afterQuote = false;
        void FinishField()
        {
            record.Add(field.ToString());
            field.Clear();
            afterQuote = false;
            if (record.Count > 5) throw new FinancePortalException(400, "CSV có quá nhiều cột.");
        }
        void FinishRecord()
        {
            FinishField();
            if (record.Any(x => !string.IsNullOrWhiteSpace(x))) records.Add(record);
            record = [];
            if (records.Count > 5001) throw new FinancePortalException(400, "Tệp đối soát tối đa 5000 dòng dữ liệu.");
        }
        // Ignore a leading UTF-8 BOM for parsing only. Hashing keeps the original evidence intact.
        for (var i = content.StartsWith('\uFEFF') ? 1 : 0; i < content.Length; i++)
        {
            var c = content[i];
            if (quoted)
            {
                if (c != '"') field.Append(c);
                else if (i + 1 < content.Length && content[i + 1] == '"') { field.Append('"'); i++; }
                else { quoted = false; afterQuote = true; }
            }
            else if (c == ',') FinishField();
            else if (c is '\n' or '\r')
            {
                if (c == '\r' && i + 1 < content.Length && content[i + 1] == '\n') i++;
                FinishRecord();
            }
            else if (afterQuote && c is ' ' or '\t') { }
            else if (afterQuote) throw new FinancePortalException(400, "CSV có ký tự thừa sau dấu nháy đóng.");
            else if (c == '"' && field.Length == 0) quoted = true;
            else if (c == '"') throw new FinancePortalException(400, "CSV có dấu nháy không hợp lệ.");
            else field.Append(c);
        }
        if (quoted) throw new FinancePortalException(400, "CSV chưa đóng dấu nháy.");
        FinishRecord();
        if (records.Count < 2 || records.Count > 5001) throw new FinancePortalException(400, "Tệp cần từ 1 đến 5000 dòng đối soát.");
        var headers = records[0].Select(x => x.Trim().TrimStart('\uFEFF')).ToList();
        var names = new[] { "transferReference", "reportedAmount", "bankStatus", "bankTransactionId", "failureReason" };
        if (headers.Count != names.Length || headers.Distinct(StringComparer.OrdinalIgnoreCase).Count() != names.Length ||
            names.Any(name => !headers.Contains(name, StringComparer.OrdinalIgnoreCase)))
            throw new FinancePortalException(400, "CSV cần 5 cột: transferReference,reportedAmount,bankStatus,bankTransactionId,failureReason.");
        var indexes = names.Select(name => headers.FindIndex(h => string.Equals(h, name, StringComparison.OrdinalIgnoreCase))).ToArray();
        var result = new List<ReconRow>();
        var references = new HashSet<string>(StringComparer.Ordinal);
        for (var i = 1; i < records.Count; i++)
        {
            var row = records[i];
            if (row.Count != 5) throw new FinancePortalException(400, $"Dòng {i}: số cột CSV không hợp lệ.");
            var reference = row[indexes[0]].Trim();
            var status = row[indexes[2]].Trim().ToUpperInvariant();
            var transaction = row[indexes[3]].Trim();
            var reason = row[indexes[4]].Trim();
            if (reference.Length is < 1 or > 80 || !references.Add(reference) ||
                !decimal.TryParse(row[indexes[1]].Trim(), NumberStyles.AllowDecimalPoint, Invariant, out var amount) ||
                amount < 0 || amount >= 10_000_000_000_000_000m || decimal.Round(amount, 2) != amount ||
                status is not ("PROCESSING" or "SUCCEEDED" or "FAILED") || transaction.Length > 100 || reason.Length > 1000 ||
                (status == "SUCCEEDED" && transaction.Length == 0) || (status == "FAILED" && reason.Length == 0))
                throw new FinancePortalException(400, $"Dòng {i}: tham chiếu, số tiền, trạng thái hoặc bằng chứng ngân hàng không hợp lệ/trùng.");
            result.Add(new ReconRow(i, reference, amount, status, transaction.Length == 0 ? null : transaction, reason.Length == 0 ? null : reason));
        }
        return result;
    }

}
