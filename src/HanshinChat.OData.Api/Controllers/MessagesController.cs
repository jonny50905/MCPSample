using HanshinChat.OData.Api.Data;
using HanshinChat.OData.Api.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.OData.Query;
using Microsoft.AspNetCore.OData.Routing.Controllers;

namespace HanshinChat.OData.Api.Controllers;

public class MessagesController : ODataController
{
    private readonly HanshinChatContext _db;

    public MessagesController(HanshinChatContext db) => _db = db;

    [EnableQuery(MaxExpansionDepth = 2, MaxAnyAllExpressionDepth = 2, PageSize = 200)]
    public IQueryable<Message> Get() => _db.Messages.AsQueryable();

    [EnableQuery(MaxExpansionDepth = 2)]
    public IActionResult Get([FromRoute] Guid key)
    {
        var entity = _db.Messages.FirstOrDefault(m => m.Id == key);
        return entity is null ? NotFound() : Ok(entity);
    }
}
