# cpolar-monitor

cpolar 隧道监控 + MoviePilot 远程更新，通过 Telegram Bot 统一控制。

## 架构

```
用户发命令 → Telegram Bot
    → Vercel Serverless (api/webhook.py)

/cpolar:
    → 登录 cpolar dashboard 获取隧道 → Telegram 回复

/update mp:
    → Maton Gateway → GitHub API
    → 触发 maton-runner/update.yml (self-hosted runner)
    → Windows 本地机器执行 update.ps1
    → 完成后 Telegram 通知结果

GitHub Actions (每10分钟，定时监控):
    → cpolar-monitor.sh run-once
    → 检测隧道变化 → Telegram 通知
```

## 功能

- 🔄 定时检查 cpolar 隧道状态（GitHub Actions，每 10 分钟）
- 📱 Telegram `/cpolar` 命令实时查询当前隧道
- 📢 隧道新增/消失时自动通知
- 🎬 Telegram `/update mp` 命令远程触发 MoviePilot 更新
- 🔒 只响应授权的 Telegram 用户
- 🪶 纯 bash + Python 标准库，无第三方依赖

## Telegram 命令

| 命令 | 功能 |
|------|------|
| `/cpolar` | 实时查询当前 cpolar 隧道地址 |
| `/update mp` 或 `/updatemp` | 触发 MoviePilot 自动更新（需要 maton-runner 在线） |

## 文件结构

```
cpolar-monitor/
├── cpolar-monitor.sh              # 主脚本（隧道检测 + Telegram 监听）
├── api/webhook.py                 # Vercel Serverless（处理 Telegram 命令）
├── .github/workflows/monitor.yml  # GitHub Actions 定时任务
├── vercel.json                    # Vercel 路由配置
├── watchdog.sh                    # 内存监控（VPS 守护进程模式用）
├── .env.example                   # 环境变量模板
└── README.md
```

## 部署

### 1. GitHub Secrets（cpolar-monitor 仓库）

| Secret | 说明 |
|--------|------|
| `CPOLAR_EMAIL` | cpolar 账号邮箱 |
| `CPOLAR_PASSWORD` | cpolar 账号密码 |
| `TELEGRAM_TOKEN` | Telegram Bot Token |
| `TELEGRAM_CHAT_ID` | 授权的 Chat ID |

### 2. Vercel 环境变量（cpolar-tg 项目）

| 变量 | 说明 |
|------|------|
| `TELEGRAM_TOKEN` | Telegram Bot Token |
| `TELEGRAM_CHAT_ID` | 授权的 Chat ID |
| `CPOLAR_EMAIL` | cpolar 账号邮箱 |
| `CPOLAR_PASSWORD` | cpolar 账号密码 |
| `MATON_API_KEY` | Maton API Key（自动注入） |

### 3. 注册 Telegram Webhook

```bash
curl -X POST "https://api.telegram.org/bot<TOKEN>/setWebhook" \
  -H "Content-Type: application/json" \
  -d '{"url": "https://cpolar-tg.vercel.app/api/webhook"}'
```

### 4. MoviePilot 更新（依赖 maton-runner）

`/update mp` 命令需要配合 [maton-runner](https://github.com/buwangni2016/maton-runner) 仓库使用：
- 在 Windows 本地机器上安装 GitHub self-hosted runner（注册到 maton-runner 仓库）
- 在 `C:\MoviePilotUpdate\update.ps1` 放置更新脚本
- 在 maton-runner 仓库 Secrets 中配置 `TELEGRAM_TOKEN` 和 `TELEGRAM_CHAT_ID`

## 本地运行（VPS 模式）

```bash
# 守护进程模式（持续监听 Telegram）
bash cpolar-monitor.sh start

# 执行一次检查后退出
bash cpolar-monitor.sh run-once

# 查看状态
bash cpolar-monitor.sh status

# 查看日志
bash cpolar-monitor.sh log
```

## License

MIT
