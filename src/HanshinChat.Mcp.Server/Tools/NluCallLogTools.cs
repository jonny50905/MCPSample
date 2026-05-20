using System.ComponentModel;
using ModelContextProtocol.Server;

namespace HanshinChat.Mcp.Server.Tools;

[McpServerToolType]
public class NluCallLogTools
{
    private readonly ODataClient _client;

    public NluCallLogTools(ODataClient client) => _client = client;

    [McpServerTool(Name = "list_nlu_logs"), Description(
        "List NLU model call logs. Use to investigate intent classification / tool-call selection behavior.")]
    public Task<string> List(
        [Description("Max rows (default 50)")] int top = 50,
        [Description("Filter by ConversationId")] Guid? conversationId = null,
        [Description("Filter by Stage (e.g. 'intent', 'tool_selection')")] string? stage = null,
        [Description("Filter by Model name (exact match)")] string? model = null,
        [Description("Only logs slower than this many milliseconds")] int? minLatencyMs = null,
        [Description("Only logs that produced an error (ErrorMessage not null)")] bool onlyErrors = false)
    {
        var filters = new List<string>();
        if (conversationId.HasValue) filters.Add($"ConversationId eq {conversationId.Value}");
        if (!string.IsNullOrWhiteSpace(stage)) filters.Add($"Stage eq '{Escape(stage)}'");
        if (!string.IsNullOrWhiteSpace(model)) filters.Add($"Model eq '{Escape(model)}'");
        if (minLatencyMs.HasValue) filters.Add($"LatencyMs ge {minLatencyMs.Value}");
        if (onlyErrors) filters.Add("ErrorMessage ne null");

        var opts = new Dictionary<string, string?>
        {
            ["filter"] = filters.Count > 0 ? string.Join(" and ", filters) : null,
            ["top"] = top.ToString(),
            ["orderby"] = "CalledAt desc",
        };
        return _client.GetAsync("NluCallLogs", opts);
    }

    [McpServerTool(Name = "get_nlu_log"), Description("Get a single NLU call log entry by Id.")]
    public Task<string> Get(
        [Description("NluCallLog Id (Guid)")] Guid id) =>
        _client.GetByKeyAsync("NluCallLogs", id);

    private static string Escape(string s) => s.Replace("'", "''");
}
