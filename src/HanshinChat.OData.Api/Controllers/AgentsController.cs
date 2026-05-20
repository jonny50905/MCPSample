using HanshinChat.OData.Api.Data;
using HanshinChat.OData.Api.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.OData.Query;
using Microsoft.AspNetCore.OData.Routing.Controllers;

namespace HanshinChat.OData.Api.Controllers;

public class AgentsController : ODataController
{
    private readonly HanshinChatContext _db;

    public AgentsController(HanshinChatContext db) => _db = db;

    [EnableQuery(MaxExpansionDepth = 2, MaxAnyAllExpressionDepth = 2, PageSize = 100)]
    public IQueryable<Agent> Get() => _db.Agents.AsQueryable();

    [EnableQuery(MaxExpansionDepth = 2)]
    public IActionResult Get([FromRoute] Guid key)
    {
        var entity = _db.Agents.FirstOrDefault(a => a.Id == key);
        return entity is null ? NotFound() : Ok(entity);
    }
}
