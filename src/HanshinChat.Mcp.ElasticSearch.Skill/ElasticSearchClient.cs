using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace HanshinChat.Mcp.ElasticSearch.Skill;

public class ElasticSearchClient
{
    private readonly HttpClient _http;
    private readonly string _defaultIndex;

    public ElasticSearchClient(HttpClient http, string defaultIndex)
    {
        _http = http;
        _defaultIndex = defaultIndex;
    }

    public string DefaultIndex => _defaultIndex;

    public string ResolveIndex(string? index) =>
        string.IsNullOrWhiteSpace(index) ? _defaultIndex : index;

    public Task<string> SearchAsync(string index, object body, CancellationToken ct = default) =>
        PostJsonAsync($"/{Uri.EscapeDataString(index)}/_search", body, ct);

    public Task<string> CountAsync(string index, object body, CancellationToken ct = default) =>
        PostJsonAsync($"/{Uri.EscapeDataString(index)}/_count", body, ct);

    public Task<string> GetDocumentAsync(string index, string id, CancellationToken ct = default) =>
        GetAsync($"/{Uri.EscapeDataString(index)}/_doc/{Uri.EscapeDataString(id)}", ct);

    public Task<string> CatIndicesAsync(CancellationToken ct = default) =>
        GetAsync("/_cat/indices?format=json&h=index,docs.count,store.size,health,status", ct);

    private async Task<string> PostJsonAsync(string path, object body, CancellationToken ct)
    {
        var json = JsonSerializer.Serialize(body);
        using var content = new StringContent(json, Encoding.UTF8, "application/json");
        try
        {
            using var resp = await _http.PostAsync(path, content, ct);
            var text = await resp.Content.ReadAsStringAsync(ct);
            return resp.IsSuccessStatusCode
                ? text
                : JsonError($"ES returned HTTP {(int)resp.StatusCode}", path, text);
        }
        catch (Exception ex)
        {
            return JsonError($"Request failed: {ex.GetType().Name}: {ex.Message}", path);
        }
    }

    private async Task<string> GetAsync(string path, CancellationToken ct)
    {
        try
        {
            using var resp = await _http.GetAsync(path, ct);
            var text = await resp.Content.ReadAsStringAsync(ct);
            return resp.IsSuccessStatusCode
                ? text
                : JsonError($"ES returned HTTP {(int)resp.StatusCode}", path, text);
        }
        catch (Exception ex)
        {
            return JsonError($"Request failed: {ex.GetType().Name}: {ex.Message}", path);
        }
    }

    private static string JsonError(string message, string url, string? body = null) =>
        JsonSerializer.Serialize(new
        {
            ok = false,
            error = message,
            url,
            response = body
        });

    public static void ConfigureAuth(HttpClient client, string? username, string? password)
    {
        if (string.IsNullOrEmpty(username) || string.IsNullOrEmpty(password)) return;
        var token = Convert.ToBase64String(Encoding.UTF8.GetBytes($"{username}:{password}"));
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Basic", token);
    }
}
