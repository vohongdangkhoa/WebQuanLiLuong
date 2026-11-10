using System.Security.Cryptography;
using System.Text;
using Payroll.Api.Contracts;
using Payroll.Api.Data;

// Pure in-memory contract checks. This program never creates an Oracle connection or changes a database.
var tests = 0;
void Check(bool condition, string label)
{
    if (!condition) throw new InvalidOperationException("FAIL: " + label);
    tests++;
    Console.WriteLine("PASS " + label);
}
int Parse(string text) => FinanceEvidence.ParseReconciliation(text).Count;
void InvalidCsv(string text, string label)
{
    try { Parse(text); throw new InvalidOperationException("FAIL: accepted " + label); }
    catch (FinancePortalException ex) { Check(ex.StatusCode == 400, label); }
}

const string header = "transferReference,reportedAmount,bankStatus,bankTransactionId,failureReason\r\n";
Check(Parse(header + "PR-1-A1,1234.50,SUCCEEDED,TEST-TX-1,\r\n") == 1, "valid evidence parsed");
Check(Parse("\uFEFF\"transferReference\",\"reportedAmount\",\"bankStatus\",\"bankTransactionId\",\"failureReason\"\r\nPR-1-A1,1,SUCCEEDED,TEST-TX-1,\r\n") == 1,
    "BOM and quoted headers accepted");
Check(Parse(header + "PR-1-A1,1,FAILED,,\"Bank said, retry\nwith evidence\"\r\n") == 1, "quoted comma and newline preserved");
InvalidCsv(header + "\"PR-1-A1\"junk,1,SUCCEEDED,TEST-TX-1,", "trailing quote junk rejected");
InvalidCsv(header + "\"PR-1-A1,1,SUCCEEDED,TEST-TX-1,", "unterminated quote rejected");
InvalidCsv(header + "PR-1-A1,1,SUCCEEDED,,", "success requires transaction evidence");
InvalidCsv(header + "PR-1-A1,1,FAILED,,", "failure requires reason");
InvalidCsv(header + "PR-1-A1,1.001,SUCCEEDED,TEST-TX-1,", "sub-cent amount rejected");
InvalidCsv(header + "PR-1-A1,1,PAID,TEST-TX-1,", "unsupported status rejected");
InvalidCsv(header + "PR-1-A1,1,SUCCEEDED,TEST-TX-1,\nPR-1-A1,1,SUCCEEDED,TEST-TX-1,", "duplicate reference rejected");
InvalidCsv("x,y\n1,2", "wrong headers rejected");

var key = RandomNumberGenerator.GetBytes(32);
var plain = Encoding.UTF8.GetBytes("001234567890");
var encrypted = FinanceEvidence.Encrypt(plain, key);
Check(encrypted.StartsWith("v1:", StringComparison.Ordinal), "versioned envelope");
Check(FinanceEvidence.Decrypt(encrypted, key).SequenceEqual(plain), "authenticated encryption round trip");
var parts = encrypted.Split(':');
var cipher = Convert.FromBase64String(parts[2]);
cipher[0] ^= 1;
parts[2] = Convert.ToBase64String(cipher);
try { FinanceEvidence.Decrypt(string.Join(':', parts), key); throw new InvalidOperationException("FAIL: tamper accepted"); }
catch (FinancePortalException ex) { Check(ex.StatusCode == 409, "tampered account rejected"); }
CryptographicOperations.ZeroMemory(key);

var csv = Encoding.UTF8.GetString(FinanceEvidence.Csv([
    new Dictionary<string, object?> { ["name"] = "=2+2", ["note"] = "quoted, \"text\"" }
]));
Check(csv.Contains("\"'=2+2\"", StringComparison.Ordinal) && csv.Contains("\"quoted, \"\"text\"\"\"", StringComparison.Ordinal),
    "CSV formula safety and escaping");
Check(FinanceErrors.Describe(54).Status == 503 && FinanceErrors.Describe(20049).Status == 409 &&
      FinanceErrors.Describe(20073).Status == 403, "busy, maker-checker and ownership errors stay controlled");
Console.WriteLine($"Finance pure checks: {tests} passed. No Oracle operations executed.");
