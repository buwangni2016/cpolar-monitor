from http.server import BaseHTTPRequestHandler
import json, os, re, urllib.request, urllib.parse, http.cookiejar

TG_TOKEN   = os.environ.get("TELEGRAM_TOKEN", "")
TG_CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID", "")
CP_EMAIL   = os.environ.get("CPOLAR_EMAIL", "")
CP_PASS    = os.environ.get("CPOLAR_PASSWORD", "")
MATON_KEY  = os.environ.get("MATON_API_KEY", "")
GH_REPO    = os.environ.get("GH_REPO", "buwangni2016/cpolar-monitor")


def cpolar_tunnels():
    cj = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
    resp = opener.open("https://dashboard.cpolar.com/login", timeout=15)
    html = resp.read().decode("utf-8", errors="ignore")
    m = re.search(r'name="csrf_token"\s+value="([^"]+)"', html)
    if not m:
        return None
    data = urllib.parse.urlencode(
        {"login": CP_EMAIL, "password": CP_PASS, "csrf_token": m.group(1)}).encode()
    req = urllib.request.Request(
        "https://dashboard.cpolar.com/login", data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded"})
    try:
        opener.open(req, timeout=15)
    except urllib.error.HTTPError:
        pass
    resp = opener.open("https://dashboard.cpolar.com/status", timeout=15)
    html = resp.read().decode("utf-8", errors="ignore")
    html_clean = re.sub(r"<script[^>]*>.*?</script>", "", html, flags=re.DOTALL)
    html_clean = re.sub(r"<style[^>]*>.*?</style>", "", html_clean, flags=re.DOTALL)
    html_clean = re.sub(r"<[^>]+>", "\n", html_clean)
    html_clean = html_clean.replace("&#43;", "+").replace("&amp;", "&")
    lines = [l.strip() for l in html_clean.split("\n") if l.strip()]
    url_re = re.compile(
        r"(https?://[a-z0-9]+\.r\d+\.cpolar\.(cn|top)"
        r"|tcp://\d+\.tcp\.cpolar\.top:\d+)")
    results = []
    for i, line in enumerate(lines):
        if url_re.match(line):
            name = ""
            for j in range(i - 1, max(i - 5, 0), -1):
                if lines[j] and not url_re.match(lines[j]) \
                        and not re.match(r"^(cn|cn_top|us|ap)$", lines[j]):
                    name = lines[j]
                    break
            results.append(f"{name or 'unknown'}|{line}")
    return sorted(set(results))


def send_tg(chat_id, text):
    payload = json.dumps(
        {"chat_id": chat_id, "text": text, "parse_mode": "HTML"}).encode()
    req = urllib.request.Request(
        f"https://api.telegram.org/bot{TG_TOKEN}/sendMessage",
        data=payload,
        headers={"Content-Type": "application/json"})
    try:
        urllib.request.urlopen(req, timeout=15)
    except Exception:
        pass


def trigger_workflow(workflow, repo=None):
    payload = json.dumps({"ref": "main"}).encode()
    req = urllib.request.Request(
        f"https://gateway.maton.ai/github/repos/{repo or GH_REPO}/actions/workflows/{workflow}/dispatches",
        data=payload,
        headers={
            "Authorization": f"Bearer {MATON_KEY}",
            "Accept": "application/vnd.github.v3+json",
            "Content-Type": "application/json",
        })
    try:
        urllib.request.urlopen(req, timeout=15)
        return True
    except urllib.error.HTTPError as e:
        return e.code == 204
    except Exception:
        return False


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")

    def do_POST(self):
        try:
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length))
            msg = body.get("message") or body.get("edited_message") or {}
            text = (msg.get("text") or "").strip()
            chat_id = str(msg.get("chat", {}).get("id", ""))
            if chat_id != TG_CHAT_ID:
                pass
            elif text == "/cpolar":
                tunnels = cpolar_tunnels()
                if tunnels:
                    lines = ["<b>📋 当前 cpolar 隧道</b>"]
                    for entry in tunnels:
                        parts = entry.split("|", 1)
                        n, u = (parts[0], parts[1]) if len(parts) == 2 else ("?", entry)
                        icon = "🖥" if u.startswith("tcp://") else "🌐"
                        lines.append(f"\n{icon} {n}\n <code>{u}</code>")
                    send_tg(chat_id, "\n".join(lines))
                else:
                    send_tg(chat_id, "❌ cpolar 登录失败")
            elif text.lower() in ("/update mp", "/updatemp"):
                send_tg(chat_id, "🔄 正在触发 MoviePilot 更新，请稍候...\n（Runner 在线时将自动执行，完成后会收到通知）")
                ok = trigger_workflow("update.yml", repo="buwangni2016/maton-runner")
                if ok:
                    send_tg(chat_id, "✅ 更新任务已成功触发，等待 Runner 执行中...")
                else:
                    send_tg(chat_id, "❌ 触发更新失败，请检查：\n1. Maton GitHub 连接是否正常\n2. maton-runner 仓库 Actions 是否启用")
        except Exception:
            pass
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")
