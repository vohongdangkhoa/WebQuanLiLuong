using Microsoft.AspNetCore.Antiforgery;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;

namespace Payroll.Api.Filters;

public class CsrfValidationFilter : IAsyncAuthorizationFilter
{
    private readonly IAntiforgery _antiforgery;

    public CsrfValidationFilter(IAntiforgery antiforgery)
    {
        _antiforgery = antiforgery;
    }
    public async Task OnAuthorizationAsync(
    AuthorizationFilterContext context)
{
    var method = context.HttpContext.Request.Method;

    if (HttpMethods.IsGet(method) ||
        HttpMethods.IsHead(method) ||
        HttpMethods.IsOptions(method) ||
        HttpMethods.IsTrace(method))
    {
        return;
    }

    try
    {
        await _antiforgery.ValidateRequestAsync(
            context.HttpContext);
    }
    catch (AntiforgeryValidationException)
    {
        context.Result = new BadRequestObjectResult(new
        {
            message = "Mã kiểm tra yêu cầu không hợp lệ. Vui lòng tải lại trang."
        });
    }
}
}