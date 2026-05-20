using HanshinChat.OData.Api.Data;
using HanshinChat.OData.Api.Middleware;
using HanshinChat.OData.Api.Models;
using Microsoft.AspNetCore.OData;
using Microsoft.EntityFrameworkCore;
using Microsoft.OData.Edm;
using Microsoft.OData.ModelBuilder;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddDbContext<HanshinChatContext>(opt =>
    opt.UseSqlServer(builder.Configuration.GetConnectionString("HanshinChat")));

builder.Services.AddControllers().AddOData(opt => opt
    .Select()
    .Filter()
    .OrderBy()
    .Expand()
    .Count()
    .SetMaxTop(1000)
    .AddRouteComponents("odata", BuildEdmModel()));

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

app.UseMiddleware<ReadOnlyMethodFilterMiddleware>();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseRouting();
app.MapControllers();

app.MapGet("/", () => Results.Redirect("/odata"));

app.Run();

static IEdmModel BuildEdmModel()
{
    var b = new ODataConventionModelBuilder();
    b.EntitySet<Agent>("Agents");
    b.EntitySet<Conversation>("Conversations");
    b.EntitySet<Message>("Messages");
    b.EntitySet<NluCallLog>("NluCallLogs");
    return b.GetEdmModel();
}
