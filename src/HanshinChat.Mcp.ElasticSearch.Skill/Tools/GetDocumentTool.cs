using System.ComponentModel;
using ModelContextProtocol.Server;

namespace HanshinChat.Mcp.ElasticSearch.Skill.Tools;

[McpServerToolType]
public class GetDocumentTool
{
    private readonly ElasticSearchClient _client;

    public GetDocumentTool(ElasticSearchClient client) => _client = client;

    [McpServerTool(Name = "get_document"), Description("Get a single document by id.")]
    public Task<string> Get(
        [Description("Document _id")] string id,
        [Description("Index name (default from appsettings)")] string? index = null)
    {
        if (string.IsNullOrWhiteSpace(id))
            return Task.FromResult("{\"ok\":false,\"error\":\"id is required\"}");
        return _client.GetDocumentAsync(_client.ResolveIndex(index), id);
    }
}
