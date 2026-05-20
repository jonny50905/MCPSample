using System.ComponentModel;
using ModelContextProtocol.Server;

namespace HanshinChat.Mcp.Server.Skill.Tools;

[McpServerToolType]
public class ODataQueryTool
{
    private readonly ODataClient _client;

    public ODataQueryTool(ODataClient client) => _client = client;

    [McpServerTool(Name = "query_odata"), Description("Generic OData query.")]
    public Task<string> Query(
        [Description("Entity set: Agents | Conversations | Messages | NluCallLogs")] string entity,
        [Description("OData $filter expression, e.g. \"Intent eq 'greeting' and IsDeleted eq false\"")] string? filter = null,
        [Description("Comma-separated OData $select fields, e.g. \"Id,Name,CreatedAt\"")] string? select = null,
        [Description("OData $orderby, e.g. \"CreatedAt desc\"")] string? orderby = null,
        [Description("Max rows (default 50, server max 1000)")] int? top = 50,
        [Description("Rows to skip (paging)")] int? skip = null,
        [Description("OData $expand, e.g. \"Messages($top=10;$orderby=CreatedAt)\"")] string? expand = null,
        [Description("If true, include @odata.count in the response")] bool? count = null)
    {
        var opts = new Dictionary<string, string?>
        {
            ["filter"] = filter,
            ["select"] = select,
            ["orderby"] = orderby,
            ["top"] = top?.ToString(),
            ["skip"] = skip?.ToString(),
            ["expand"] = expand,
            ["count"] = count == true ? "true" : null,
        };
        return _client.GetAsync(entity, opts);
    }
}
