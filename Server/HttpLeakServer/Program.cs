using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

var builder = WebApplication.CreateBuilder(args);

builder.Logging.ClearProviders();
builder.Logging.AddSimpleConsole(options =>
{
    options.SingleLine = true;
    options.TimestampFormat = "HH:mm:ss ";
});

var app = builder.Build();

app.MapGet("/", () => Results.Text("ok"));
app.MapGet("/ping", () => Results.Text("ok"));
app.MapGet("/slow", async () =>
{
    await Task.Delay(50);
    return Results.Text("ok");
});

var url = Environment.GetEnvironmentVariable("HTTPLEAK_URL") ?? "http://localhost:5055";
app.Urls.Add(url);

app.Lifetime.ApplicationStarted.Register(() =>
{
    Console.WriteLine($"Listening on {url}");
});

await app.RunAsync();
