using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace HanshinChat.OData.Api.Models;

[Table("NluCallLogs")]
public class NluCallLog
{
    [Key]
    public Guid Id { get; set; }

    public Guid? ConversationId { get; set; }

    public DateTime CalledAt { get; set; }

    [Required, MaxLength(32)]
    public string Stage { get; set; } = string.Empty;

    [Required, MaxLength(2000)]
    public string UserText { get; set; } = string.Empty;

    [Required, MaxLength(64)]
    public string Model { get; set; } = string.Empty;

    [Required]
    public string SystemPrompt { get; set; } = string.Empty;

    [Required]
    public string ToolsJson { get; set; } = string.Empty;

    [MaxLength(128)]
    public string? ResultToolName { get; set; }

    public string? ResultArgsJson { get; set; }

    public string? ResultRawResponse { get; set; }

    public string? SuggestionsJson { get; set; }

    public int? InputTokens { get; set; }

    public int? OutputTokens { get; set; }

    public int LatencyMs { get; set; }

    public string? ErrorMessage { get; set; }

    [ForeignKey(nameof(ConversationId))]
    public Conversation? Conversation { get; set; }
}
