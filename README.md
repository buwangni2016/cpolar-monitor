# cpolar-monitor

轻量级 cpolar 隧道监控工具，隧道地址变化时通过 Telegram 实时通知。

## 功能

- 🔄 定时检查 cpolar 隧道状态（默认每 10 分钟）
- 📱 Telegram Bot 监听 `/cpolar` 命令，随时查询当前隧道
- 📢 隧道新增/消失时实时通知
- 🔒 只响应授权的 Telegram 用户
- 🪶 纯 bash + curl + python3，无额外依赖

## 快速开始

```bash
# 1. 克隆仓库
git clone https://github.com/buwangni2016/cpolar-monitor.git
cd cpolar-monitor

# 2. 配置
cp .env.example .env
vim .env  # 填入你的 cpolar 账号和 Telegram Bot 信息

# 3. 启动
chmod +x cpolar-monitor.sh
./cpolar-monitor.sh start
```

## 命令

| 命令 | 说明 |
|------|------|
| `./cpolar-monitor.sh start` | 后台启动守护进程 |
| `./cpolar-monitor.sh stop` | 停止守护进程 |
| `./cpolar-monitor.sh status` | 查看运行状态和当前隧道 |
| `./cpolar-monitor.sh log [n]` | 查看最近 n 行日志（默认 20） |
| `./cpolar-monitor.sh run` | 前台运行（调试用） |
| `./cpolar-monitor.sh run-once` | 执行一次检查后退出（CI/CD 用） |

## Telegram Bot 命令

| 命令 | 说明 |
|------|------|
| `/cpolar` | 查看当前隧道状态 |

## Telegram Bot 配置

1. 找 [@BotFather](https://t.me/BotFather) 创建 Bot，获取 Token
2. 给 Bot 发任意消息
3. 访问 `https://api.telegram.org/bot<token>/getUpdates` 获取你的 chat_id
4. 填入 `.env` 文件

## Watchdog（自动重启）

配合 crontab 实现自动重启：

```bash
# 每 5 分钟检查一次，如果守护进程挂了就自动重启
*/5 * * * * /path/to/cpolar-monitor/watchdog.sh
```

## GitHub Actions（免 VPS 方案）

无需 VPS，利用 GitHub Actions 每 10 分钟自动检查：

1. Fork 本仓库
2. 在仓库 Settings → Secrets and variables → Actions 中添加：
   - `CPOLAR_EMAIL` — cpolar 账号邮箱
   - `CPOLAR_PASSWORD` — cpolar 密码
   - `TELEGRAM_TOKEN` — Telegram Bot Token
   - `TELEGRAM_CHAT_ID` — Telegram Chat ID
3. 启用 Actions（首次 Fork 需手动启用）
4. Cookie 和隧道状态通过 `actions/cache` 持久化

> ⚠️ GitHub Actions 免费账户每月 2000 分钟，每 10 分钟一次约用 1440 分钟/月，注意额度。

## 依赖

- bash 4+
- curl
- python3（HTML 解析）

## 已知问题

- cpolar 登录页 `/login` 可能返回 404（网页改版），但 POST 到 `/login` 仍可登录
- Cookie 有效期约 24 小时，过期后脚本会自动尝试重新登录
- 如果登录接口也失效，脚本会停止工作，需要手动刷新 cookie

## 安全提示

- ⚠️ **不要**将 `.env` 文件提交到 Git
- `.env` 已在 `.gitignore` 中排除

## License

MIT
