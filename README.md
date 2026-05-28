# cpolar-monitor

cpolar 隧道监控 + Telegram 通知，隧道变化时自动告警，支持 `/cpolar` 命令随时查询。

## 架构

```
用户发 /cpolar → Telegram Bot
    → Vercel Serverless (api/webhook.py)
    → 登录 cpolar 获取隧道 → Telegram 回复

GitHub Actions (每10分钟)
    → cpolar-monitor.sh run-once
    → 检测隧道变化 → Telegram 通知
```

## 功能

- 🔄 定时检查 cpolar 隧道状态（GitHub Actions，每 10 分钟）
- 📱 Telegram `/cpolar` 命令实时查询当前隧道
- 📢 隧道新增/消失时自动通知
- 🔒 只响应授权的 Telegram 用户
- 🪶 纯 bash + Python 标准库，无第三方依赖

## 文件结构

```
cpolar-monitor/
├── cpolar-monitor.sh              # 主脚本（隧道检测 + Telegram 监听）
├── api/webhook.py                 # Vercel Serverless（处理 /cpolar 命令）
├── .github/workflows/monitor.yml  # GitHub Actions 定时任务
├── vercel.json                    # Vercel 路由配置
├── watchdog.sh                    # 内存监控（VPS 守护进程模式用）
├── .env.example                   # 环境变量模板
└── README.md
```

## 部署

### 1. GitHub Secrets

| Secret | 说明 |
|--------|------|
| `CPOLAR_EMAIL` | cpolar 账号邮箱 |
| `CPOLAR_PASSWORD` | cpolar 账号密码 |
| `TELEGRAM_TOKEN` | Telegram Bot Token |
| `TELEGRAM_CHAT_ID` | 授权的 Chat ID |

### 2. Vercel 环境变量

同上 4 个变量，在 Vercel 项目 Settings → Environment Variables 中配置。

### 3. Telegram Webhook

```bash
curl -X POST "https://api.telegram.org/bot<TOKEN>/setWebhook"   -H "Content-Type: application/json"   -d '{"url": "https://<PROJECT>.vercel.app/api/webhook"}'
```

## 使用

```
/cpolar    查询当前隧道状态
```

GitHub Actions 自动运行，无需手动操作。

## 本地运行

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
