# HttpClient 连接池/端口耗尽实验报告（重跑 2026-01-19）

## 实验目标
验证“每请求 new HttpClient 并 using 释放”在高并发下会导致 TIME_WAIT 激增，并对比复用 HttpClient / IHttpClientFactory 的表现。

## 实验环境
- OS: Windows
- SDK: .NET SDK 10.0.102
- 运行时: .NET 6/8/10, .NET Framework 4.8
- 服务器: HttpLeakServer（target net6，通过 roll-forward 运行）
- 客户端: net48 / net6 / net8 / net10
- 压测参数: requests=20000, parallel=200, timeoutSeconds=5
- TIME_WAIT 统计: `netstat -an` 过滤端口 5055
- 隔离策略: 每轮结束后等待 TIME_WAIT <= baseline + 200（每 10 秒检查，最长 300 秒）

## 运行方式
- 先在后台启动 Server（`dotnet run --project Server/HttpLeakServer/HttpLeakServer.csproj --no-build`）
- 再运行脚本：[scripts/run-experiment-external-server.ps1](scripts/run-experiment-external-server.ps1)
- 本次日志目录：[logs/run-20260119-095017](logs/run-20260119-095017)

## 关键结果
### TIME_WAIT 统计（端口 5055）
| 时点                | TIME_WAIT | ESTABLISHED | CLOSE_WAIT |
| ------------------- | --------- | ----------- | ---------- |
| before-net48        | 2         | 0           | 0          |
| after-net48         | 20002     | 0           | 0          |
| before-net6         | 0         | 0           | 0          |
| after-net6          | 20000     | 0           | 0          |
| before-net8         | 0         | 0           | 0          |
| after-net8          | 18361     | 0           | 0          |
| before-net10-new    | 0         | 0           | 0          |
| after-net10-new     | 18860     | 0           | 0          |
| before-net10-static | 0         | 0           | 0          |
| after-net10-static  | 202       | 0           | 0          |
| before-net10-factory| 200       | 0           | 0          |
| after-net10-factory | 200       | 0           | 0          |

来源：[logs/run-20260119-095017/netstat.log](logs/run-20260119-095017/netstat.log)

### 客户端执行结果（摘要）
- net48: success=20000, failed=0
- net6: success=20000, failed=0
- net8: success=18361, failed=1639（报错：“通常每个套接字地址只允许使用一次”）
- net10-new: success=18860, failed=1140（报错：“通常每个套接字地址只允许使用一次”）
- net10-static: success=20000, failed=0
- net10-factory: success=20000, failed=0

来源：[logs/run-20260119-095017/*.out.log](logs/run-20260119-095017/*.out.log)

## 结论与措辞调整
1. 在 net48/net6/net8/net10-new（每请求 new HttpClient）场景下，TIME_WAIT 明显激增（约 1.8 万到 2 万）。
2. 复用 HttpClient 或使用 `IHttpClientFactory` 显著降低 TIME_WAIT：本次 net10-static 与 net10-factory 维持在 200 量级，且请求全部成功。
3. 本次参数下 net8 与 net10-new 出现“每个套接字地址只允许使用一次”错误（分别 1639/1140 次），net48/net6 无失败。因此结论更适合表述为“频繁 new HttpClient 会显著增加 TIME_WAIT 并提升端口耗尽风险”，而非“必然导致大量失败”。

## 局限与备注
- 客户端与服务器同机，TIME_WAIT 统计包含两端连接，不能完全归因于客户端端口耗尽。
- net48 客户端设置了 `ServicePointManager.DefaultConnectionLimit = 1000`，与 net6+/net10 的连接管理策略存在差异。

## 相关日志
- [logs/run-20260119-095017/netstat.log](logs/run-20260119-095017/netstat.log)
- [logs/run-20260119-095017/cooldown.log](logs/run-20260119-095017/cooldown.log)
- [logs/run-20260119-095017/experiment-summary.log](logs/run-20260119-095017/experiment-summary.log)
- [logs/run-20260119-095017/net48.out.log](logs/run-20260119-095017/net48.out.log)
- [logs/run-20260119-095017/net6.out.log](logs/run-20260119-095017/net6.out.log)
- [logs/run-20260119-095017/net8.out.log](logs/run-20260119-095017/net8.out.log)
- [logs/run-20260119-095017/net10-new.out.log](logs/run-20260119-095017/net10-new.out.log)
- [logs/run-20260119-095017/net10-static.out.log](logs/run-20260119-095017/net10-static.out.log)
- [logs/run-20260119-095017/net10-factory.out.log](logs/run-20260119-095017/net10-factory.out.log)
