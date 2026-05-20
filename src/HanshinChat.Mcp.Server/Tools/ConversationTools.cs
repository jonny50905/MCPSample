using System.ComponentModel;
using System.Globalization;
using ModelContextProtocol.Server;

namespace HanshinChat.Mcp.Server.Tools;

[McpServerToolType]
public class ConversationTools
{
    private readonly ODataClient _client;

    public ConversationTools(ODataClient client) => _client = client;

    [McpServerTool(Name = "list_conversations"), Description(
        "List conversations from HanshinChat. Supports filtering by mode, channel, member, and time range.")]
    public Task<string> List(
        [Description("Max rows (default 50)")] int top = 50,
        [Description("Filter by Mode (e.g. 'AI', 'Human', 'Queue')")] string? mode = null,
        [Description("Filter by Channel (e.g. 'Web', 'LINE')")] string? channel = null,
        [Description("Filter by MemberId (exact)")] string? memberId = null,
        [Description("Only conversations started on/after this UTC time (ISO-8601, e.g. 2026-05-01T00:00:00Z)")] string? startedAfter = null,
        [Description("Only conversations still open (ClosedAt is null)")] bool onlyOpen = false,
        [Description("If true, also expand the conversation's messages (first 50, sorted)")] bool includeMessages = false)
    {
        var filters = new List<string>();
        if (!string.IsNullOrWhiteSpace(mode)) filters.Add($"Mode eq '{Escape(mode)}'");
        if (!string.IsNullOrWhiteSpace(channel)) filters.Add($"Channel eq '{Escape(channel)}'");
        if (!string.IsNullOrWhiteSpace(memberId)) filters.Add($"MemberId eq '{Escape(memberId)}'");
        if (!string.IsNullOrWhiteSpace(startedAfter) && DateTime.TryParse(startedAfter, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var dt))
            filters.Add($"StartedAt ge {dt:yyyy-MM-ddTHH:mm:ssZ}");
        if (onlyOpen) filters.Add("ClosedAt eq null");

        var opts = new Dictionary<string, string?>
        {
            ["filter"] = filters.Count > 0 ? string.Join(" and ", filters) : null,
            ["top"] = top.ToString(),
            ["orderby"] = "StartedAt desc",
            ["expand"] = includeMessages ? "Messages($top=50;$orderby=CreatedAt)" : null,
        };
        return _client.GetAsync("Conversations", opts);
    }

    [McpServerTool(Name = "get_conversation"), Description(
        "Get a single conversation by Id. By default expands its messages (first 100, in chronological order).")]
    public Task<string> Get(
        [Description("Conversation Id (Guid)")] Guid id,
        [Description("Include messages via $expand (default true)")] bool includeMessages = true)
    {
        var opts = new Dictionary<string, string?>();
        if (includeMessages)
            opts["expand"] = "Messages($top=100;$orderby=CreatedAt)";
        return _client.GetByKeyAsync("Conversations", id, opts);
    }

    private static string Escape(string s) => s.Replace("'", "''");
}
