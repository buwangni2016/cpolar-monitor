# cpolar-monitor

杞婚噺绾?cpolar 闅ч亾鐩戞帶宸ュ叿锛岄毀閬撳湴鍧€鍙樺寲鏃堕€氳繃 Telegram 瀹炴椂閫氱煡銆?
## 鍔熻兘

- 馃攧 瀹氭椂妫€鏌?cpolar 闅ч亾鐘舵€侊紙榛樿姣?10 鍒嗛挓锛?- 馃摫 Telegram Bot 鐩戝惉 `/cpolar` 鍛戒护锛岄殢鏃舵煡璇㈠綋鍓嶉毀閬?- 馃敂 闅ч亾鏂板/娑堝け鏃跺疄鏃堕€氱煡
- 馃敀 鍙搷搴旀巿鏉冪殑 Telegram 鐢ㄦ埛
- 馃 绾?bash + curl + python3锛屾棤棰濆渚濊禆

## 蹇€熷紑濮?
```bash
# 1. 鍏嬮殕浠撳簱
git clone https://github.com/buwangni2016/cpolar-monitor.git
cd cpolar-monitor

# 2. 閰嶇疆
cp .env.example .env
vim .env  # 濉叆浣犵殑 cpolar 璐﹀彿鍜?Telegram Bot 淇℃伅

# 3. 鍚姩
chmod +x cpolar-monitor.sh
./cpolar-monitor.sh start
```

## 鍛戒护

| 鍛戒护 | 璇存槑 |
|------|------|
| `./cpolar-monitor.sh start` | 鍚庡彴鍚姩瀹堟姢杩涚▼ |
| `./cpolar-monitor.sh stop` | 鍋滄瀹堟姢杩涚▼ |
| `./cpolar-monitor.sh status` | 鏌ョ湅杩愯鐘舵€佸拰褰撳墠闅ч亾 |
| `./cpolar-monitor.sh log [n]` | 鏌ョ湅鏈€杩?n 琛屾棩蹇楋紙榛樿 20锛?|
| `./cpolar-monitor.sh run` | 鍓嶅彴杩愯锛堣皟璇曠敤锛?|

## Telegram Bot 鍛戒护

| 鍛戒护 | 璇存槑 |
|------|------|
| `/cpolar` | 鏌ョ湅褰撳墠闅ч亾鐘舵€?|

## Telegram Bot 閰嶇疆

1. 鎵?[@BotFather](https://t.me/BotFather) 鍒涘缓 Bot锛岃幏鍙?Token
2. 缁?Bot 鍙戜换鎰忔秷鎭?3. 璁块棶 `https://api.telegram.org/bot<token>/getUpdates` 鑾峰彇浣犵殑 chat_id
4. 濉叆 `.env` 鏂囦欢

## 閫氱煡鏍峰紡

```
馃搵 褰撳墠 cpolar 闅ч亾

馃寪 moviepolite
 https://xxxx.r9.cpolar.cn
馃枼 remoteDesktop
 tcp://x.tcp.cpolar.top:xxxxx
馃寪 tunnel-1
 https://xxxx.r8.cpolar.top

馃晲 2026-05-27 05:43:24
```

## 渚濊禆

- bash 4+
- curl
- python3锛圚TML 瑙ｆ瀽锛?
## 瀹夊叏鎻愮ず

- 鈿狅笍 **涓嶈**灏?`.env` 鏂囦欢鎻愪氦鍒?Git
- `.env` 宸插湪 `.gitignore` 涓帓闄?
## License

MIT
