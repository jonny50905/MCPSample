using System.ComponentModel;
using ModelContextProtocol.Server;

namespace HanshinChat.Mcp.Server.Skill.Tools;

[McpServerToolType]
public class MessageTools
{
    private readonly ODataClient _client;

    public MessageTools(ODataClient client) => _client = client;

    [McpServerTool(Name = "list_messages"), Description("List messages.")]
    public Task<string> List(
        [Description("Max rows (default 100, server max 1000)")] int top = 100,
        [Description("Filter by ConversationId (Guid)")] Guid? conversationId = null,
        [Description("Filter by SenderType (e.g. 'User', 'Bot', 'Agent')")] string? senderType = null,
        [Description("Filter by Intent (exact match, e.g. 'greeting')")] string? intent = null,
        [Description("Include messages flagged IsDeleted (default false)")] bool includeDeleted = false,
        [Description("Order: 'desc' (newest first, default) or 'asc'")] string order = "desc")
    {
        var filters = new List<string>();
        if (conversationId.HasValue) filters.Add($"ConversationId eq {conversationId.Value}");
        if (!string.IsNullOrWhiteSpace(senderType)) filters.Add($"SenderType eq '{Escape(senderType)}'");
        if (!string.IsNullOrWhiteSpace(intent)) filters.Add($"Intent eq '{Escape(intent)}'");
        if (!includeDeleted) filters.Add("IsDeleted eq false");

        var orderby = string.Equals(order, "asc", StringComparison.OrdinalIgnoreCase) ? "CreatedAt asc" : "CreatedAt desc";

        var opts = new Dictionary<string, string?>
        {
            ["filter"] = filters.Count > 0 ? string.Join(" and ", filters) : null,
            ["top"] = top.ToString(),
            ["orderby"] = orderby,
        };
        return _client.GetAsync("Messages", opts);
    }

    [McpServerTool(Name = "search_messages"), Description("Full-text search messages.")]
    public Task<string> Search(
        [Description("Substring to look for inside ContentJson")] string text,
        [Description("Max rows (default 50)")] int top = 50,
        [Description("Optionally restrict to a single conversation")] Guid? conversationId = null)
    {
        if (string.IsNullOrWhiteSpace(text))
            return Task.FromResult("{\"ok\":false,\"error\":\"text is required\"}");

        var filters = new List<string> { $"contains(ContentJson,'{Escape(text)}')", "IsDeleted eq false" };
        if (conversationId.HasValue) filters.Add($"ConversationId eq {conversationId.Value}");

        var opts = new Dictionary<string, string?>
        {
            ["filter"] = string.Join(" and ", filters),
            ["top"] = top.ToString(),
            ["orderby"] = "CreatedAt desc",
        };
        return _client.GetAsync("Messages", opts);
    }

    [McpServerTool(Name = "get_message"), Description("Get message by Id.")]
    public Task<string> Get(
        [Description("Message Id (Guid)")] Guid id) =>
        _client.GetByKeyAsync("Messages", id);

    private static string Escape(string s) => s.Replace("'", "''");
}
