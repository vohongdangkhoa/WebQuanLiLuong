using Payroll.Api.Data;
using Microsoft.AspNetCore.Identity;
using Payroll.Api.Services;
using Microsoft.AspNetCore.Authentication.Cookies;
using Payroll.Api.Filters;
var builder = WebApplication.CreateBuilder(args);
// Add services to the container.
builder.Services.AddCors(options =>
{
    options.AddPolicy("ReactFrontend", policy =>
    {
        policy.WithOrigins("http://localhost:5173")
              .AllowAnyHeader()
              .AllowAnyMethod()
              .AllowCredentials();
    });
});
// Add services to the container.

builder.Services.AddControllers(options =>
{
    options.Filters.AddService<CsrfValidationFilter>();
});
builder.Services.AddAntiforgery(options =>
{
    options.HeaderName = "X-CSRF-TOKEN";

    options.Cookie.Name = "Payroll.Csrf";
    options.Cookie.HttpOnly = true;
    options.Cookie.SameSite = SameSiteMode.Lax;
    options.Cookie.SecurePolicy = CookieSecurePolicy.SameAsRequest;
});
builder.Services.AddScoped<OracleConnectionFactory>();
builder.Services.AddScoped<OracleAuthRepository>();
builder.Services.AddScoped<OracleEmployeeRepository>();
builder.Services.AddScoped<OracleDepartmentRepository>();
builder.Services.AddScoped<OracleJobPositionRepository>();
builder.Services.AddScoped<IPasswordHasher<AuthUser>, PasswordHasher<AuthUser>>();
builder.Services.AddScoped<AuthService>();
builder.Services.AddScoped<PayrollCookieEvents>();
builder.Services.AddScoped<CsrfValidationFilter>();
builder.Services.AddAuthentication(
    CookieAuthenticationDefaults.AuthenticationScheme)
    .AddCookie(options =>
    {
        options.EventsType = typeof(PayrollCookieEvents);
        options.Cookie.Name = "Payroll.Auth";
        options.Cookie.HttpOnly = true;
        options.Cookie.SameSite = SameSiteMode.Lax;
        options.Cookie.SecurePolicy = CookieSecurePolicy.SameAsRequest;

        options.ExpireTimeSpan = TimeSpan.FromMinutes(30);
        options.SlidingExpiration = false;
    });

// Learn more about configuring OpenAPI at https://aka.ms/aspnet/openapi
builder.Services.AddOpenApi();

/* AddProblemDetails(...): đăng ký cách trả thông tin lỗi theo dạng JSON chuẩn.
Status >= 500: áp dụng thông báo chung cho lỗi phía máy chủ.
Title: nội dung thông báo lỗi. */
builder.Services.AddProblemDetails(options =>
{
    options.CustomizeProblemDetails = context =>
    {
        if (context.ProblemDetails.Status >= 500)
        {
            context.ProblemDetails.Title =
                "Máy chủ gặp lỗi. Vui lòng thử lại sau.";

            context.ProblemDetails.Detail = null;
        }
    };
});

var app = builder.Build();

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.UseRouting();
app.UseCors("ReactFrontend");
app.UseExceptionHandler();/* UseExceptionHandler(): bắt các lỗi chưa được xử lý ở những phần chạy phía sau nó. Đặt trước UseAuthentication() giúp bắt được cả lỗi khi kiểm tra phiên đăng nhập. Tài liệu Microsoft */
app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();

app.Run();