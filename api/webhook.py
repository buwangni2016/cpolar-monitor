from http.server import BaseHTTPRequestHandler
import json, os, re, urllib.request, urllib.parse, http.cookiejar, base64

# ─── Config ───
TG_TOKEN   = os.environ.get("TELEGRAM_TOKEN", "")
TG_CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID", "")
CP_EMAIL   = os.environ.get("CPOLAR_EMAIL", "")
CP_PASS    = os.environ.get("CPOLAR_PASSWORD", "")
REDIS_URL  = os.environ.get("UPSTASH_REDIS_REST_URL", "")
REDIS_TOK  = os.environ.get("UPSTASH_REDIS_REST_TOKEN", "")


def redis_get(key):
    if not REDIS_URL:
        return None
    try:
        req = urllib.request.Request(
            f"{REDIS_URL}/get/{key}",
            headers={"Authorization": f"Bearer {REDIS_TOK}"})
        with urllib.request.urlopen(req, timeout=5) as r:
            data = json.loads(r.read())
            val = data.get("result")
            if val:
                return base64.b64decode(val).decode("utf-8")
    except Exception:
        pass
    return None


def redis_set(key, value, ttl_sec=82800):
    if not REDIS_URL:
        return
    try:
        encoded = base64.b64encode(value.encode("utf-8")).decode()
        req = urllib.request.Request(
            f"{REDIS_URL}/set/{key}/{encoded}?EX={ttl_sec}",
            headers={"Authorization": f"Bearer {REDIS_TOK}"},
            method="POST")
        urllib.request.urlopen(req, timeout=5)
    except Exception:
        pass


def cpolar_login():
    cj = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
    # GET login page for CSRF token
    resp = opener.open("https://dashboard.cpolar.com/login", timeout=15)
    html = resp.read().decode("utf-8", errors="ignore")
    m = re.search(r'name="csrf_token"\s+value="([^"]+)"', html)
    if not m:
        return None, None
    csrf = m.group(1)
    # POST login
    data = urllib.parse.urlencode(
        {"login": CP_EMAIL, "password": CP_PASS, "csrf_token": csrf}).encode()
    req = urllib.request.Request(
        "https://dashboard.cpolar.com/login",
        data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded"})
    try:
        opener.open(req, timeout=15)
    except urllib.error.HTTPError:
        pass
    # Extract cookies as JSON
    cookies = {}
    for c in cj:
        cookies[c.name] = c.value
    if not cookies:
        return None, None
    return json.dumps(cookies), cj


def cpolar_tunnels(cookie_json=None):
    cj = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
    # Load saved cookies
    if cookie_json:
        try:
            for name, value in json.loads(cookie_json).items():
                c = http.cookiejar.Cookie(
                    0, name, value, None, False, ".dashboard.cpolar.com",
                    None, "/", "/", False, False, 0, False, None, None, {})
                cj.set_cookie(c)
        except Exception:
            pass
    # Fetch status
    resp = opener.open("https://dashboard.cpolar.com/status", timeout=15)
    html = resp.read().decode("utf-8", errors="ignore")
    # Check if login required
    if "captcha-form" in html or "/login" in html:
        cookie_json, cj2 = cpolar_login()
        if not cookie_json:
            return None, None
        opener2 = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(cj2))
        resp = opener2.open("https://dashboard.cpolar.com/status", timeout=15)
        html = resp.read().decode("utf-8", errors="ignore")
    # Parse tunnels (same logic as cpolar-monitor.sh)
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
                if lines[j] and not url_re.match(lines[j])                         and not re.match(r"^(cn|cn_top|us|ap)$", lines[j]):
                    name = lines[j]
                    break
            results.append(f"{name or 'unknown'}|{line}")
    return sorted(set(results)), cookie_json


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
            text = msg.get("text", "")
            chat_id = str(msg.get("chat", {}).get("id", ""))
            if text != "/cpolar" or chat_id != TG_CHAT_ID:
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"ok")
                return

            # ─── Handle /cpolar ───
            cookie_val = redis_get("cpolar:cookie")
            tunnels, cookie_val = cpolar_tunnels(cookie_val)
            if cookie_val:
                redis_set("cpolar:cookie", cookie_val)

            if tunnels:
                lines = ["📋 <b>当前 cpolar 隧道</b>"]
                for entry in tunnels:
                    name, url = entry.split("|", 1) if "|" in entry else ("?", entry)
                    icon = "🖥" if url.startswith("tcp://") else "🌐"
                    lines.append(f"\n{icon} {name}\n <code>{url}</code>")
                send_tg(chat_id, "\n".join(lines))
            else:
                send_tg(chat_id, "❌ cpolar 登录失败或无隧道")
        except Exception:
            pass

        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")
