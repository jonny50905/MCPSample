using System.ComponentModel;
using ModelContextProtocol.Server;

namespace HanshinChat.Mcp.ElasticSearch.Skill.Tools;

[McpServerToolType]
public class CountTool
{
    private readonly ElasticSearchClient _client;

    public CountTool(ElasticSearchClient client) => _client = client;

    [McpServerTool(Name = "count"), Description("Count documents matching a Lucene query.")]
    public Task<string> Count(
        [Description("Lucene query string (use \"*:*\" for all docs)")] string query,
        [Description("Index name (default from appsettings)")] string? index = null)
    {
        if (string.IsNullOrWhiteSpace(query))
            return Task.FromResult("{\"ok\":false,\"error\":\"query is required\"}");

        var body = new
        {
            query = new { query_string = new { query } }
        };
        return _client.CountAsync(_client.ResolveIndex(index), body);
    }
}
