using HanshinChat.OData.Api.Models;
using Microsoft.EntityFrameworkCore;

namespace HanshinChat.OData.Api.Data;

public class HanshinChatContext : DbContext
{
    public HanshinChatContext(DbContextOptions<HanshinChatContext> options) : base(options)
    {
    }

    public DbSet<Agent> Agents => Set<Agent>();
    public DbSet<Conversation> Conversations => Set<Conversation>();
    public DbSet<Message> Messages => Set<Message>();
    public DbSet<NluCallLog> NluCallLogs => Set<NluCallLog>();

    protected override void OnConfiguring(DbContextOptionsBuilder optionsBuilder)
    {
        optionsBuilder.UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking);
        base.OnConfiguring(optionsBuilder);
    }

    public override int SaveChanges() =>
        throw new InvalidOperationException("HanshinChat OData layer is read-only.");

    public override int SaveChanges(bool acceptAllChangesOnSuccess) =>
        throw new InvalidOperationException("HanshinChat OData layer is read-only.");

    public override Task<int> SaveChangesAsync(CancellationToken cancellationToken = default) =>
        throw new InvalidOperationException("HanshinChat OData layer is read-only.");

    public override Task<int> SaveChangesAsync(bool acceptAllChangesOnSuccess, CancellationToken cancellationToken = default) =>
        throw new InvalidOperationException("HanshinChat OData layer is read-only.");
}
