using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace HanshinChat.OData.Api.Models;

[Table("Messages")]
public class Message
{
    [Key]
    public Guid Id { get; set; }

    public Guid ConversationId { get; set; }

    [Required, MaxLength(10)]
    public string SenderType { get; set; } = string.Empty;

    [MaxLength(64)]
    public string? SenderId { get; set; }

    [MaxLength(100)]
    public string? SenderName { get; set; }

    [Required]
    public string ContentJson { get; set; } = string.Empty;

    [MaxLength(100)]
    public string? Intent { get; set; }

    public double? Confidence { get; set; }

    public Guid? TraceId { get; set; }

    public DateTime CreatedAt { get; set; }

    public bool IsDeleted { get; set; }

    [ForeignKey(nameof(ConversationId))]
    public Conversation? Conversation { get; set; }
}
