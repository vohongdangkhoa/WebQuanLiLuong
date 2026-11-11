using Microsoft.AspNetCore.Diagnostics;
using Oracle.ManagedDataAccess.Client;

namespace Payroll.Api.Services;

public sealed class ApiExceptionHandler(ILogger<ApiExceptionHandler> logger) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(HttpContext context, Exception error, CancellationToken token)
    {
        var (status, message) = error switch
        {
            PlatformException e => (e.StatusCode, e.Message),
            OracleException { Number: 20002 } => (403, "Bạn không có quyền thực hiện thao tác này."),
            OracleException { Number: 1 } => (409, "Dữ liệu đã tồn tại hoặc trùng với một bản ghi hiện có."),
            OracleException { Number: 54 } => (503, "Dữ liệu đang được xử lý. Vui lòng thử lại sau."),
            OracleException e when e.Number is 904 or 942 or 6550 or 6553 =>
                (503, "Hệ thống chưa được cập nhật database đầy đủ. Hãy liên hệ người quản trị."),
            OracleException e when e.Number is 4061 or 4063 or 4065 or 4068 =>
                (503, "Oracle đang nạp lại chương trình. Hãy thử lại sau vài giây."),
            OracleException e when e.Number is 1017 or 3113 or 3114 or 3135 or 12154 or 12170 or 12514 or 12537 or 12541 or 12570 or 28000 =>
                (503, "Chưa kết nối được cơ sở dữ liệu. Vui lòng kiểm tra dịch vụ Oracle."),
            OracleException e when e.Number is >= 20000 and <= 20999 =>
                (409, "Thao tác chưa phù hợp với trạng thái hoặc dữ liệu hiện tại. Vui lòng kiểm tra lại."),
            OracleException e when e.Number is 1400 or 1438 or 2290 or 2291 or 2292 or 12899 =>
                (400, "Dữ liệu không đáp ứng các ràng buộc của hệ thống. Vui lòng kiểm tra lại."),
            _ => (500, "Có lỗi khi xử lý yêu cầu. Hãy thử lại.")
        };
        if (status >= 500)
        {
            var endpoint = context.GetEndpoint() ?? context.Features.Get<IExceptionHandlerFeature>()?.Endpoint;
            var route = (endpoint as RouteEndpoint)?.RoutePattern.RawText;
            logger.LogError(error, "Request failed {Method} {Route} {TraceId}", context.Request.Method, route, context.TraceIdentifier);
        }
        else logger.LogWarning("Request rejected {Status} {TraceId}", status, context.TraceIdentifier);
        context.Response.StatusCode = status;
        context.Response.Headers.CacheControl = "no-store";
        await context.Response.WriteAsJsonAsync(new { message, traceId = context.TraceIdentifier }, token);
        return true;
    }
}

public sealed class PlatformException(string message, int statusCode = 409) : Exception(message)
{
    public int StatusCode { get; } = statusCode;
}
