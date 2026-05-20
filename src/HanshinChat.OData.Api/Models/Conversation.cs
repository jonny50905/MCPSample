using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace HanshinChat.OData.Api.Models;

[Table("Conversations")]
public class Conversation
{
    [Key]
    public Guid Id { get; set; }

    [MaxLength(64)]
    public string? MemberId { get; set; }

    [Required, MaxLength(20)]
    public string Mode { get; set; } = string.Empty;

    public Guid? AssignedAgentId { get; set; }

    public int? QueuePosition { get; set; }

    [Required, MaxLength(20)]
    public string Channel { get; set; } = string.Empty;

    public DateTime StartedAt { get; set; }

    public DateTime? ClosedAt { get; set; }

    public string? Metadata { get; set; }

    [ForeignKey(nameof(AssignedAgentId))]
    public Agent? AssignedAgent { get; set; }

    public ICollection<Message> Messages { get; set; } = new List<Message>();
}
