using HanshinChat.OData.Api.Data;
using HanshinChat.OData.Api.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.OData.Query;
using Microsoft.AspNetCore.OData.Routing.Controllers;

namespace HanshinChat.OData.Api.Controllers;

public class ConversationsController : ODataController
{
    private readonly HanshinChatContext _db;

    public ConversationsController(HanshinChatContext db) => _db = db;

    [EnableQuery(MaxExpansionDepth = 2, MaxAnyAllExpressionDepth = 2, PageSize = 100)]
    public IQueryable<Conversation> Get() => _db.Conversations.AsQueryable();

    [EnableQuery(MaxExpansionDepth = 2)]
    public IActionResult Get([FromRoute] Guid key)
    {
        var entity = _db.Conversations.FirstOrDefault(c => c.Id == key);
        return entity is null ? NotFound() : Ok(entity);
    }
}
