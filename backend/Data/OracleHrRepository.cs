using System.Data;
using System.Data.Common;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using Microsoft.VisualBasic.FileIO;
using Oracle.ManagedDataAccess.Client;
using Oracle.ManagedDataAccess.Types;

namespace Payroll.Api.Data;

public sealed class OracleHrRepository(OracleConnectionFactory connectionFactory, IHostEnvironment environment)
{
    public static OracleParameter Number(string name, object? value) => new(name, OracleDbType.Decimal) { Value = value ?? DBNull.Value };
    public static OracleParameter Text(string name, string? value) => new(name, OracleDbType.Varchar2) { Value = (object?)value ?? DBNull.Value };
    public static OracleParameter Day(string name, DateOnly? value) => new(name, OracleDbType.Date)
    {
        Value = value is null ? DBNull.Value : value.Value.ToDateTime(TimeOnly.MinValue, DateTimeKind.Unspecified)
    };
    public static OracleParameter Time(string name, DateTime? value)
    {
        if (value is not null && value.Value.Kind != DateTimeKind.Unspecified)
            throw new HrInputException("Thời gian cần theo giờ Việt Nam, không kèm Z hoặc múi giờ.");
        return new(name, OracleDbType.TimeStamp) { Value = (object?)value ?? DBNull.Value };
    }

    public async Task<List<Dictionary<string, object?>>> ReadAsync(long actorId, string resource, long? periodId, long? employeeId, CancellationToken ct)
    {
        using var connection = connectionFactory.CreateConnection();
        await connection.OpenAsync(ct);
        using var command = connection.CreateCommand();
        command.CommandText = "PAYROLL_APP.PKG_HR_PORTAL.read_data";
        command.CommandType = CommandType.StoredProcedure;
        command.BindByName = true;
        command.Parameters.Add(Number("p_actor", actorId));
        command.Parameters.Add(Text("p_resource", resource));
        command.Parameters.Add(Number("p_period", periodId));
        command.Parameters.Add(Number("p_employee", employeeId));
        command.Parameters.Add("p_rows", OracleDbType.RefCursor).Direction = ParameterDirection.Output;
        using var reader = await command.ExecuteReaderAsync(ct);
        var rows = new List<Dictionary<string, object?>>();
        while (await reader.ReadAsync(ct))
        {
            var row = new Dictionary<string, object?>();
            for (var index = 0; index < reader.FieldCount; index++)
            {
                var name = CamelCase(reader.GetName(index));
                row[name] = FieldValue(reader, index);
            }
            rows.Add(row);
        }
        return rows;
    }

    public async Task<long?> WriteAsync(long actorId, string procedure, OracleParameter[] parameters, bool returnsId, CancellationToken ct)
    {
        using var connection = connectionFactory.CreateConnection();
        await connection.OpenAsync(ct);
        using var transaction = connection.BeginTransaction();
        using var command = CreateCommand(connection, actorId, procedure, parameters);
        OracleParameter? output = null;
        if (returnsId)
        {
            output = command.Parameters.Add("p_id", OracleDbType.Decimal);
            output.Direction = ParameterDirection.Output;
        }
        await command.ExecuteNonQueryAsync(ct);
        long? id = output is null ? null : OutputId(output);
        transaction.Commit();
        return id;
    }

    public async Task<List<Dictionary<string, object?>>> ReadCalendarAsync(long actorId, long calendarId, DateOnly? month, CancellationToken ct)
    {
        using var connection = connectionFactory.CreateConnection();
        await connection.OpenAsync(ct);
        using var command = CreateCommand(connection, actorId, "PAYROLL_APP.PKG_HR_PORTAL.read_calendar", [Number("p_calendar", calendarId), Day("p_month", month)]);
        command.Parameters.Add("p_rows", OracleDbType.RefCursor).Direction = ParameterDirection.Output;
        using var reader = await command.ExecuteReaderAsync(ct);
        var rows = new List<Dictionary<string, object?>>();
        while (await reader.ReadAsync(ct))
        {
            var row = new Dictionary<string, object?>();
            for (var index = 0; index < reader.FieldCount; index++)
                row[CamelCase(reader.GetName(index))] = FieldValue(reader, index);
            rows.Add(row);
        }
        return rows;
    }

    public async Task<object> ImportAttendanceAsync(long actorId, IFormFile file, CancellationToken ct)
    {
        if (file.Length is <= 0 or > 2 * 1024 * 1024 || !string.Equals(Path.GetExtension(file.FileName), ".csv", StringComparison.OrdinalIgnoreCase))
            throw new HrInputException("Chọn tệp CSV có dữ liệu, dung lượng tối đa 2 MB.");
        await using var memory = new MemoryStream();
        await file.CopyToAsync(memory, ct);
        var bytes = memory.ToArray();
        var content = new UTF8Encoding(false, true).GetString(bytes).TrimStart('\uFEFF');
        var records = ParseAttendanceCsv(content);
        var hash = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
        var relativeKey = "attendance/" + hash + ".csv";
        var directory = Path.Combine(environment.ContentRootPath, "data", "attendance");
        Directory.CreateDirectory(directory);
        var storagePath = Path.Combine(directory, hash + ".csv");
        if (!File.Exists(storagePath))
            await File.WriteAllBytesAsync(storagePath, bytes, ct);

        using var connection = connectionFactory.CreateConnection();
        await connection.OpenAsync(ct);
        using var transaction = connection.BeginTransaction();
        using var start = CreateCommand(connection, actorId, "PAYROLL_APP.PKG_HR_PORTAL.start_import", [
            Text("p_hash", hash), Text("p_storage_key", relativeKey), Text("p_name", Path.GetFileName(file.FileName)), Number("p_size", bytes.Length)]);
        var importId = start.Parameters.Add("p_id", OracleDbType.Decimal);
        importId.Direction = ParameterDirection.Output;
        var existing = start.Parameters.Add("p_existing", OracleDbType.Decimal);
        existing.Direction = ParameterDirection.Output;
        await start.ExecuteNonQueryAsync(ct);
        var id = OutputId(importId);
        if (((OracleDecimal)existing.Value).Value == 1)
        {
            transaction.Rollback();
            return new { id, importedRows = 0, skippedDuplicates = records.Count, validationErrors = 0, alreadyImported = true, message = "Tệp này đã được nhập trước đó, dữ liệu không bị nhân đôi." };
        }
        var importedRows = 0;
        foreach (var record in records)
        {
            using var append = CreateCommand(connection, actorId, "PAYROLL_APP.PKG_HR_PORTAL.append_raw", [
                Number("p_import", id), Text("p_employee_code", record.EmployeeCode), Time("p_event", record.EventAt),
                Text("p_type", record.EventType), Text("p_device", record.SourceDevice), Text("p_key", record.SourceEventKey)]);
            var inserted = append.Parameters.Add("p_inserted", OracleDbType.Decimal);
            inserted.Direction = ParameterDirection.Output;
            await append.ExecuteNonQueryAsync(ct);
            importedRows += (int)((OracleDecimal)inserted.Value).Value;
        }
        using var finish = CreateCommand(connection, actorId, "PAYROLL_APP.PKG_HR_PORTAL.finish_import", [Number("p_import", id)]);
        var errorCount = finish.Parameters.Add("p_errors", OracleDbType.Decimal);
        errorCount.Direction = ParameterDirection.Output;
        await finish.ExecuteNonQueryAsync(ct);
        var validationErrors = checked((int)((OracleDecimal)errorCount.Value).Value);
        transaction.Commit();
        return new { id, importedRows, skippedDuplicates = records.Count - importedRows, validationErrors, alreadyImported = false, message = "Đã lưu dữ liệu máy chấm công gốc. HR cần đối chiếu và xác nhận công trước khi chốt." };
    }

    private static OracleCommand CreateCommand(OracleConnection connection, long actorId, string procedure, OracleParameter[] parameters)
    {
        var command = connection.CreateCommand();
        command.CommandText = procedure;
        command.CommandType = CommandType.StoredProcedure;
        command.BindByName = true;
        command.Parameters.Add(Number("p_actor", actorId));
        command.Parameters.AddRange(parameters);
        return command;
    }

    private static long OutputId(OracleParameter parameter)
    {
        var value = (OracleDecimal)parameter.Value;
        if (value.IsNull || !value.IsInt || !value.IsPositive)
            throw new InvalidOperationException("Oracle trả về mã định danh không hợp lệ.");
        return checked((long)value.Value);
    }

    private static string CamelCase(string name)
    {
        var parts = name.ToLowerInvariant().Split('_');
        return parts[0] + string.Concat(parts.Skip(1).Select(part => char.ToUpperInvariant(part[0]) + part[1..]));
    }

    private static object? FieldValue(DbDataReader reader, int index)
    {
        if (reader.IsDBNull(index)) return null;
        // Read the provider value first: GetValue may discard the TZ wrapper.
        // Plain DATE/TIMESTAMP and preformatted Vietnam wall-time strings stay unchanged.
        return reader.GetProviderSpecificValue(index) is OracleTimeStampTZ timestamp
            ? UtcTimestamp(timestamp)
            : reader.GetValue(index);
    }

    private static string? UtcTimestamp(OracleTimeStampTZ timestamp) => timestamp.IsNull
        ? null
        : DateTime.SpecifyKind(timestamp.ToUniversalTime().Value, DateTimeKind.Utc)
            .ToString("O", CultureInfo.InvariantCulture);

    private sealed record RawAttendance(string EmployeeCode, DateTime EventAt, string EventType, string SourceDevice, string SourceEventKey);

    private static List<RawAttendance> ParseAttendanceCsv(string content)
    {
        using var parser = new TextFieldParser(new StringReader(content));
        parser.SetDelimiters(",");
        parser.HasFieldsEnclosedInQuotes = true;
        parser.TrimWhiteSpace = true;
        string[]? header;
        try { header = parser.ReadFields(); }
        catch (MalformedLineException) { throw new HrInputException("Dòng tiêu đề CSV không đúng định dạng."); }
        string[] required = ["employeeCode", "eventAt", "eventType", "sourceDevice", "sourceEventKey"];
        if (header is null || !header.SequenceEqual(required, StringComparer.OrdinalIgnoreCase))
            throw new HrInputException("CSV cần các cột: employeeCode,eventAt,eventType,sourceDevice,sourceEventKey.");
        var rows = new List<RawAttendance>();
        while (!parser.EndOfData)
        {
            string[]? fields;
            try { fields = parser.ReadFields(); }
            catch (MalformedLineException) { throw new HrInputException($"CSV sai định dạng tại dòng {parser.ErrorLineNumber}."); }
            if (fields is null) continue;
            var line = rows.Count + 2;
            if (rows.Count >= 5000) throw new HrInputException("Mỗi lần nhập tối đa 5.000 dòng.");
            if (fields.Length != 5 || fields[0].Length is 0 or > 50 || fields[3].Length is 0 or > 80 || fields[4].Length is 0 or > 100 ||
                !DateTime.TryParseExact(fields[1], ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm"], CultureInfo.InvariantCulture, DateTimeStyles.None, out var eventAt) ||
                fields[2].ToUpperInvariant() is not ("IN" or "OUT" or "UNKNOWN"))
                throw new HrInputException($"Dữ liệu dòng {line} không hợp lệ. Giờ dùng dạng 2026-11-05T08:00:00; loại sự kiện IN/OUT/UNKNOWN.");
            rows.Add(new(fields[0], eventAt, fields[2].ToUpperInvariant(), fields[3], fields[4]));
        }
        if (rows.Count == 0) throw new HrInputException("CSV chưa có dòng dữ liệu.");
        return rows;
    }
}

public sealed class HrInputException(string message) : Exception(message) { }
