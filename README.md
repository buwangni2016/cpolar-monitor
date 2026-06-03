# cpolar-monitor

部署在 Vercel 的 Telegram Bot webhook，提供两个命令：

- `/cpolar` — 查询当前 cpolar 隧道列表
- `/update mp` — 触发 MoviePilot 自动更新

## 架构

```
Telegram → Vercel webhook (api/webhook.py)
                ├─ /cpolar    → 直接登录 cpolar dashboard 抓取隧道信息
                └─ /update mp → 触发 maton-runner/update.yml (via Maton API Gateway)
                                        └─ Windows Runner 执行更新脚本
```

## 文件说明

| 文件 | 说明 |
|------|------|
| `api/webhook.py` | Vercel serverless 入口，处理 Telegram 消息 |
| `cpolar-monitor.sh` | cpolar 隧道变化监控脚本（供 monitor.yml 手动触发使用）|
| `.github/workflows/monitor.yml` | 手动触发的 cpolar 监控（已关闭定时调度）|
| `vercel.json` | Vercel 路由配置 |

## Vercel 环境变量

| 变量 | 说明 |
|------|------|
| `TELEGRAM_TOKEN` | Bot Token |
| `TELEGRAM_CHAT_ID` | 授权的 Chat ID（只响应此 ID 的消息）|
| `CPOLAR_EMAIL` | cpolar 账号 |
| `CPOLAR_PASSWORD` | cpolar 密码 |
| `MATON_API_KEY` | Maton API Key，用于调用 GitHub Actions |

## 相关仓库

- [maton-runner](https://github.com/buwangni2016/maton-runner) — Windows Runner，执行 MoviePilot 更新
- [maton-agent-memory](https://github.com/buwangni2016/maton-agent-memory) — 项目完整说明文档
