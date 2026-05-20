using System.ComponentModel;
using ModelContextProtocol.Server;

namespace HanshinChat.Mcp.Server.Skill.Tools;

[McpServerToolType]
public class AgentTools
{
    private readonly ODataClient _client;

    public AgentTools(ODataClient client) => _client = client;

    [McpServerTool(Name = "list_agents"), Description("List agents.")]
    public Task<string> List(
        [Description("Max rows (default 50)")] int top = 50,
        [Description("Filter by online status")] bool? isOnline = null,
        [Description("Filter agents whose Name contains this substring")] string? nameContains = null,
        [Description("Filter by EmployeeId (exact match)")] string? employeeId = null)
    {
        var filters = new List<string>();
        if (isOnline.HasValue) filters.Add($"IsOnline eq {(isOnline.Value ? "true" : "false")}");
        if (!string.IsNullOrWhiteSpace(nameContains)) filters.Add($"contains(Name,'{Escape(nameContains)}')");
        if (!string.IsNullOrWhiteSpace(employeeId)) filters.Add($"EmployeeId eq '{Escape(employeeId)}'");

        var opts = new Dictionary<string, string?>
        {
            ["filter"] = filters.Count > 0 ? string.Join(" and ", filters) : null,
            ["top"] = top.ToString(),
            ["orderby"] = "Name asc",
        };
        return _client.GetAsync("Agents", opts);
    }

    [McpServerTool(Name = "get_agent"), Description("Get agent by Id.")]
    public Task<string> Get(
        [Description("Agent Id (Guid)")] Guid id) =>
        _client.GetByKeyAsync("Agents", id);

    private static string Escape(string s) => s.Replace("'", "''");
}
