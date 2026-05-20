using HanshinChat.Mcp.Server;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

var builder = Host.CreateApplicationBuilder(args);

builder.Logging.ClearProviders();
builder.Logging.AddConsole(o =>
{
    o.LogToStandardErrorThreshold = LogLevel.Trace;
});

var odataBaseUrl = builder.Configuration["OData:BaseUrl"]
    ?? "http://localhost:5050/odata/";
if (!odataBaseUrl.EndsWith("/")) odataBaseUrl += "/";

builder.Services.AddHttpClient<ODataClient>(c =>
{
    c.BaseAddress = new Uri(odataBaseUrl);
    c.DefaultRequestHeaders.Accept.Add(new("application/json"));
});

builder.Services
    .AddMcpServer()
    .WithStdioServerTransport()
    .WithToolsFromAssembly();

await builder.Build().RunAsync();
