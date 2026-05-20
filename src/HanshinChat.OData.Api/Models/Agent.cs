using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace HanshinChat.OData.Api.Models;

[Table("Agents")]
public class Agent
{
    [Key]
    public Guid Id { get; set; }

    [Required, MaxLength(64)]
    public string EmployeeId { get; set; } = string.Empty;

    [Required, MaxLength(100)]
    public string Name { get; set; } = string.Empty;

    [MaxLength(500)]
    public string? AvatarUrl { get; set; }

    public bool IsOnline { get; set; }

    public DateTime CreatedAt { get; set; }
}
