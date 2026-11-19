using Oracle.ManagedDataAccess.Client;

namespace Payroll.Api.Data;

internal static class OracleReaderExtensions
{
    internal static async Task<bool> ReadRowAsync(this OracleDataReader reader, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        // A canceled ODP.NET fetch can also interrupt a subsequent read. Observe
        // cancellation between fetches instead of forwarding it into this driver call.
        var hasRow = await reader.ReadAsync(CancellationToken.None);
        cancellationToken.ThrowIfCancellationRequested();
        return hasRow;
    }
}
