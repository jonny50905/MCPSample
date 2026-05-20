using System.Text.Json;

namespace HanshinChat.OData.Api.Middleware;

public class ReadOnlyMethodFilterMiddleware
{
    private static readonly HashSet<string> WriteMethods = new(StringComparer.OrdinalIgnoreCase)
    {
        "POST", "PUT", "PATCH", "DELETE", "MERGE"
    };

    private readonly RequestDelegate _next;

    public ReadOnlyMethodFilterMiddleware(RequestDelegate next)
    {
        _next = next;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        var path = context.Request.Path.Value ?? string.Empty;
        if (path.StartsWith("/odata", StringComparison.OrdinalIgnoreCase) &&
            WriteMethods.Contains(context.Request.Method))
        {
            context.Response.StatusCode = StatusCodes.Status405MethodNotAllowed;
            context.Response.ContentType = "application/json";
            context.Response.Headers.Allow = "GET";
            var payload = JsonSerializer.Serialize(new
            {
                error = "This OData endpoint is read-only.",
                method = context.Request.Method,
                path
            });
            await context.Response.WriteAsync(payload);
            return;
        }

        await _next(context);
    }
}
