#!/usr/bin/env bash
# Локальная демонстрация веб-версии: раздаёт build/web по сети со сжатием.
# Заказчик открывает ссылку вида http://<ваш-IP>:8080 из той же сети.
set -e
cd "$(dirname "$0")"

FLUTTER_BIN="${FLUTTER_BIN:-$HOME/Downloads/flutter/bin/flutter}"
PORT="${1:-8080}"

if [ ! -f build/web/index.html ]; then
  echo "Собираю веб-версию…"
  "$FLUTTER_BIN" build web --release
fi

IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo 127.0.0.1)"
echo "Ссылка для показа: http://$IP:$PORT"
echo "Остановить: Ctrl+C"
exec python3 serve_web.py "$PORT"
