using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Identity;
using Payroll.Api.Data;
using Payroll.Api.Filters;
using Payroll.Api.Services;

var builder = WebApplication.CreateBuilder(args);
var localDirectory = Path.Combine(builder.Environment.ContentRootPath, ".local");
Directory.CreateDirectory(localDirectory);
var protection = builder.Services.AddDataProtection()
    .SetApplicationName("Payroll.Api")
    .PersistKeysToFileSystem(new DirectoryInfo(Path.Combine(localDirectory, "keys")));
if (OperatingSystem.IsWindows()) protection.ProtectKeysWithDpapi();
builder.Services.AddCors(options => options.AddPolicy("ReactFrontend", policy =>
    policy.WithOrigins(builder.Configuration.GetSection("Frontend:Origins").Get<string[]>()
            ?? ["http://localhost:5173", "http://localhost:5174"])
        .AllowAnyHeader().AllowAnyMethod().AllowCredentials()));
builder.Services.AddControllers(options => options.Filters.AddService<CsrfValidationFilter>());
builder.Services.AddAntiforgery(options =>
{
    options.HeaderName = "X-CSRF-TOKEN";
    options.Cookie.Name = "Payroll.Csrf";
    options.Cookie.HttpOnly = true;
    options.Cookie.SameSite = SameSiteMode.Lax;
    options.Cookie.SecurePolicy = builder.Environment.IsDevelopment()
        ? CookieSecurePolicy.SameAsRequest : CookieSecurePolicy.Always;
});
builder.Services.AddScoped<OracleConnectionFactory>();
builder.Services.AddScoped<OracleAuthRepository>();
builder.Services.AddScoped<OracleEmployeeRepository>();
builder.Services.AddScoped<OracleDepartmentRepository>();
builder.Services.AddScoped<OracleJobPositionRepository>();
builder.Services.AddScoped<OraclePlatformRepository>();
builder.Services.AddScoped<OracleFinanceRepository>();
builder.Services.AddScoped<OracleHrRepository>();
builder.Services.AddScoped<OracleConfigurationRepository>();
builder.Services.AddScoped<IPasswordHasher<AuthUser>, PasswordHasher<AuthUser>>();
builder.Services.AddScoped<AuthService>();
builder.Services.AddScoped<PayrollCookieEvents>();
builder.Services.AddScoped<CsrfValidationFilter>();
builder.Services.AddSingleton<BankSecurityService>();
builder.Services.AddExceptionHandler<ApiExceptionHandler>();
builder.Services.AddProblemDetails();
builder.Services.AddAuthentication(CookieAuthenticationDefaults.AuthenticationScheme)
    .AddCookie(options =>
    {
        options.EventsType = typeof(PayrollCookieEvents);
        options.Cookie.Name = "Payroll.Auth";
        options.Cookie.HttpOnly = true;
        options.Cookie.SameSite = SameSiteMode.Lax;
        options.Cookie.SecurePolicy = builder.Environment.IsDevelopment()
            ? CookieSecurePolicy.SameAsRequest : CookieSecurePolicy.Always;
        options.ExpireTimeSpan = TimeSpan.FromMinutes(30);
        options.SlidingExpiration = false;
    });
builder.Services.AddAuthorization();
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.AddPolicy("login", context => RateLimitPartition.GetFixedWindowLimiter(
        context.Connection.RemoteIpAddress?.ToString() ?? "local",
        _ => new FixedWindowRateLimiterOptions
        { PermitLimit = 15, Window = TimeSpan.FromMinutes(1), QueueLimit = 0 }));
    options.OnRejected = async (context, token) =>
        await context.HttpContext.Response.WriteAsJsonAsync(new
        { message = "Bạn thử đăng nhập quá nhiều lần. Vui lòng chờ một phút." }, token);
});
builder.Services.AddOpenApi();
var app = builder.Build();
if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
    app.Services.GetRequiredService<BankSecurityService>().EnsureDevelopmentKey();
}
else app.UseHsts();
app.UseExceptionHandler();
app.Use(async (context, next) =>
{
    context.Response.Headers.XContentTypeOptions = "nosniff";
    context.Response.Headers["Referrer-Policy"] = "same-origin";
    context.Response.Headers["X-Frame-Options"] = "DENY";
    await next();
});
app.UseDefaultFiles();
app.UseStaticFiles();
app.UseRouting();
app.UseCors("ReactFrontend");
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();
app.MapFallback("/api/{**path}", () => Results.NotFound(new { message = "Không tìm thấy API." }));
if (File.Exists(Path.Combine(app.Environment.WebRootPath ?? "wwwroot", "index.html")))
    app.MapFallbackToFile("index.html");
app.Run();

public partial class Program;
