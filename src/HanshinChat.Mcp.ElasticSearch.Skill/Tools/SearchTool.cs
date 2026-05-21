using System.ComponentModel;
using ModelContextProtocol.Server;

namespace HanshinChat.Mcp.ElasticSearch.Skill.Tools;

[McpServerToolType]
public class SearchTool
{
    private readonly ElasticSearchClient _client;

    public SearchTool(ElasticSearchClient client) => _client = client;

    [McpServerTool(Name = "search"), Description("Full-text search via Lucene query string.")]
    public Task<string> Search(
        [Description("Lucene query string, e.g. \"Content:運送\", \"Intent:complaint AND CreatedAt:[2026-05-15 TO *]\"")] string query,
        [Description("Index name (default from appsettings)")] string? index = null,
        [Description("Max hits (default 10)")] int size = 10,
        [Description("Offset for paging (default 0)")] int from = 0,
        [Description("Restrict _source to these fields (default all)")] string[]? fields = null)
    {
        if (string.IsNullOrWhiteSpace(query))
            return Task.FromResult("{\"ok\":false,\"error\":\"query is required\"}");

        var body = new Dictionary<string, object?>
        {
            ["from"] = from,
            ["size"] = size,
            ["query"] = new
            {
                query_string = new { query }
            },
            ["highlight"] = new
            {
                fields = new Dictionary<string, object> { ["*"] = new { fragment_size = 150, number_of_fragments = 3 } },
                pre_tags = new[] { "<em>" },
                post_tags = new[] { "</em>" }
            }
        };
        if (fields is { Length: > 0 }) body["_source"] = fields;

        return _client.SearchAsync(_client.ResolveIndex(index), body);
    }
}
