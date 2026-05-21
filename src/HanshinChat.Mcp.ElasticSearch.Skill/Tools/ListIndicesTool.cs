using System.ComponentModel;
using System.Text.Json;
using System.Text.Json.Nodes;
using ModelContextProtocol.Server;

namespace HanshinChat.Mcp.ElasticSearch.Skill.Tools;

[McpServerToolType]
public class ListIndicesTool
{
    private readonly ElasticSearchClient _client;

    public ListIndicesTool(ElasticSearchClient client) => _client = client;

    [McpServerTool(Name = "list_indices"), Description("List user indices (system indices starting with '.' are filtered out).")]
    public async Task<string> List()
    {
        var raw = await _client.CatIndicesAsync();

        try
        {
            var node = JsonNode.Parse(raw);
            if (node is not JsonArray arr) return raw;

            var filtered = new JsonArray();
            foreach (var item in arr)
            {
                if (item is JsonObject o &&
                    o["index"]?.GetValue<string>() is { } name &&
                    !name.StartsWith('.'))
                {
                    filtered.Add(item!.DeepClone());
                }
            }
            return filtered.ToJsonString(new JsonSerializerOptions
            {
                Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping
            });
        }
        catch
        {
            return raw;
        }
    }
}
