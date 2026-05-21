using HanshinChat.Mcp.ElasticSearch.Skill;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

var builder = Host.CreateApplicationBuilder(args);

builder.Logging.ClearProviders();
builder.Logging.AddConsole(o =>
{
    o.LogToStandardErrorThreshold = LogLevel.Trace;
});

var baseUrl = builder.Configuration["ElasticSearch:BaseUrl"] ?? "http://localhost:9200";
var defaultIndex = builder.Configuration["ElasticSearch:DefaultIndex"] ?? "hanshinchat-messages";
var username = builder.Configuration["ElasticSearch:Username"];
var password = builder.Configuration["ElasticSearch:Password"];

builder.Services.AddHttpClient("es", c =>
{
    c.BaseAddress = new Uri(baseUrl);
    c.DefaultRequestHeaders.Accept.Add(new("application/json"));
    ElasticSearchClient.ConfigureAuth(c, username, password);
});

builder.Services.AddSingleton(sp =>
{
    var http = sp.GetRequiredService<IHttpClientFactory>().CreateClient("es");
    return new ElasticSearchClient(http, defaultIndex);
});

builder.Services
    .AddMcpServer()
    .WithStdioServerTransport()
    .WithToolsFromAssembly();

await builder.Build().RunAsync();
