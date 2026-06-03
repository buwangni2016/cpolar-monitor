# cpolar-monitor

部署在 Vercel 的 Telegram Bot webhook，提供两个命令：

- `/cpolar` — 查询当前 cpolar 隧道列表
- `/update mp` — 触发 MoviePilot 自动更新

## 关联仓库

```
[cpolar-monitor] ──触发──▶ [maton-runner] ──文档──▶ [maton-agent-memory]
  本仓库（Webhook）           Windows Runner            项目总览文档
  接收 Telegram 命令           执行更新脚本
```

| 仓库 | 作用 | 链接 |
|------|------|------|
| **cpolar-monitor**（本仓库） | 接收 Telegram 命令，触发下游 Runner | — |
| **maton-runner**（下游） | Windows Runner，执行 MoviePilot 完整更新流程 | [buwangni2016/maton-runner](https://github.com/buwangni2016/maton-runner) |
| **maton-agent-memory**（文档） | 三个仓库的完整架构说明与上下文 | [buwangni2016/maton-agent-memory](https://github.com/buwangni2016/maton-agent-memory) |

## 架构

```
用户
 ↓ 发送命令
Telegram Bot
 ↓ POST
Vercel webhook (api/webhook.py)
 ├─ /cpolar    → 登录 cpolar dashboard 抓取隧道信息 → 回复 Telegram
 └─ /update mp → Maton API Gateway → maton-runner/update.yml（workflow_dispatch）
                                              ↓
                                     Windows Runner 执行更新
                                              ↓
                                     Telegram 通知结果
```

## 文件说明

| 文件 | 说明 |
|------|------|
| `api/webhook.py` | Vercel serverless 入口，处理 Telegram 消息 |
| `cpolar-monitor.sh` | cpolar 隧道变化监控脚本 |
| `.github/workflows/monitor.yml` | 手动触发的 cpolar 监控（定时调度已关闭，避免消耗 Actions 额度）|
| `vercel.json` | Vercel 路由配置 |

## Vercel 环境变量

| 变量 | 说明 |
|------|------|
| `TELEGRAM_TOKEN` | Bot Token |
| `TELEGRAM_CHAT_ID` | 授权的 Chat ID（只响应此 ID 的消息，其他一律忽略）|
| `CPOLAR_EMAIL` | cpolar 账号 |
| `CPOLAR_PASSWORD` | cpolar 密码 |
| `MATON_API_KEY` | Maton API Key，用于通过 API Gateway 触发 maton-runner 的 GitHub Actions |
| `GH_REPO` | 默认值 `buwangni2016/maton-runner`（触发 workflow_dispatch 的目标仓库）|

## 安全说明

- 只响应 `TELEGRAM_CHAT_ID` 匹配的消息，其他用户的请求静默忽略（返回 200）
- MATON_API_KEY 通过 Vercel 环境变量注入，不在代码中硬编码
