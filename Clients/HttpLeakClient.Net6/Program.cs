using System.Diagnostics;
using System.Net.Http;

static string? GetArg(string[] args, string name)
{
    for (var i = 0; i < args.Length - 1; i++)
    {
        if (string.Equals(args[i], name, StringComparison.OrdinalIgnoreCase))
        {
            return args[i + 1];
        }
    }

    return null;
}

static int GetArgInt(string[] args, string name, int defaultValue)
{
    var value = GetArg(args, name);
    return int.TryParse(value, out var parsed) ? parsed : defaultValue;
}

var url = GetArg(args, "--url") ?? "http://localhost:5055/ping";
var requests = GetArgInt(args, "--requests", 20000);
var parallel = GetArgInt(args, "--parallel", 200);
var logEvery = GetArgInt(args, "--logEvery", 1000);
var timeoutSeconds = GetArgInt(args, "--timeoutSeconds", 5);

Console.WriteLine($"url={url}");
Console.WriteLine($"requests={requests}, parallel={parallel}, timeoutSeconds={timeoutSeconds}");

var throttler = new SemaphoreSlim(parallel);
var tasks = new List<Task>(requests);
var sw = Stopwatch.StartNew();
var success = 0;
var failed = 0;

for (var i = 0; i < requests; i++)
{
    await throttler.WaitAsync();
    var index = i + 1;
    tasks.Add(Task.Run(async () =>
    {
        try
        {
            using var client = new HttpClient();
            client.Timeout = TimeSpan.FromSeconds(timeoutSeconds);
            using var response = await client.GetAsync(url);
            response.EnsureSuccessStatusCode();
            Interlocked.Increment(ref success);
        }
        catch (Exception ex)
        {
            var fail = Interlocked.Increment(ref failed);
            if (fail <= 5)
            {
                Console.WriteLine($"ERR#{fail}: {ex.GetType().Name} {ex.Message}");
            }
        }
        finally
        {
            throttler.Release();
        }
    }));

    if (index % logEvery == 0)
    {
        Console.WriteLine($"queued: {index}/{requests}, success: {Volatile.Read(ref success)}, failed: {Volatile.Read(ref failed)}, elapsed: {sw.Elapsed}");
    }
}

await Task.WhenAll(tasks);
Console.WriteLine($"done: success={success}, failed={failed}, elapsed={sw.Elapsed}");
