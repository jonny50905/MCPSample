using System.Text;

namespace HanshinChat.Mcp.Server;

public class ODataClient
{
    private static readonly HashSet<string> AllowedEntities = new(StringComparer.OrdinalIgnoreCase)
    {
        "Agents", "Conversations", "Messages", "NluCallLogs"
    };

    private readonly HttpClient _http;

    public ODataClient(HttpClient http)
    {
        _http = http;
    }

    public static bool IsAllowedEntity(string entity) => AllowedEntities.Contains(entity);

    public static IEnumerable<string> Entities => AllowedEntities;

    public async Task<string> GetAsync(string entity, IDictionary<string, string?> options, CancellationToken ct = default)
    {
        if (!IsAllowedEntity(entity))
        {
            return JsonError("Unknown entity. Allowed: " + string.Join(", ", AllowedEntities), $"entity={entity}");
        }

        var url = BuildUrl(entity, options);
        try
        {
            var resp = await _http.GetAsync(url, ct);
            var body = await resp.Content.ReadAsStringAsync(ct);
            if (!resp.IsSuccessStatusCode)
            {
                return JsonError($"OData returned HTTP {(int)resp.StatusCode}", url, body);
            }
            return body;
        }
        catch (Exception ex)
        {
            return JsonError($"Request failed: {ex.GetType().Name}: {ex.Message}", url);
        }
    }

    public async Task<string> GetByKeyAsync(string entity, Guid key, IDictionary<string, string?>? options = null, CancellationToken ct = default)
    {
        if (!IsAllowedEntity(entity))
        {
            return JsonError("Unknown entity. Allowed: " + string.Join(", ", AllowedEntities), $"entity={entity}");
        }

        var path = $"{entity}({key})";
        var url = options is { Count: > 0 } ? path + "?" + BuildQueryString(options) : path;
        try
        {
            var resp = await _http.GetAsync(url, ct);
            var body = await resp.Content.ReadAsStringAsync(ct);
            if (!resp.IsSuccessStatusCode)
            {
                return JsonError($"OData returned HTTP {(int)resp.StatusCode}", url, body);
            }
            return body;
        }
        catch (Exception ex)
        {
            return JsonError($"Request failed: {ex.GetType().Name}: {ex.Message}", url);
        }
    }

    private static string BuildUrl(string entity, IDictionary<string, string?> options)
    {
        var qs = BuildQueryString(options);
        return string.IsNullOrEmpty(qs) ? entity : $"{entity}?{qs}";
    }

    private static string BuildQueryString(IDictionary<string, string?> options)
    {
        var sb = new StringBuilder();
        foreach (var kv in options)
        {
            if (string.IsNullOrWhiteSpace(kv.Value)) continue;
            if (sb.Length > 0) sb.Append('&');
            sb.Append('$').Append(kv.Key).Append('=').Append(Uri.EscapeDataString(kv.Value));
        }
        return sb.ToString();
    }

    private static string JsonError(string message, string url, string? body = null)
    {
        var escaped = System.Text.Json.JsonSerializer.Serialize(new
        {
            ok = false,
            error = message,
            url,
            response = body
        });
        return escaped;
    }
}
