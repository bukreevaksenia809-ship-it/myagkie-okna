#!/usr/bin/env bash
# Сборка веб-версии и публикация на боевой адрес Firebase Hosting.
#
# Первый аргумент — цель хостинга (target) из firebase.json / .firebaserc:
#   excl (по умолчанию) → https://myagkie-okna-excl.web.app — «Мягкие окна Excl»
#   v1                  → https://okna-7dbf8.web.app        — «Мягкие окна 1»
# Проект можно переопределить переменной PROJECT (по умолчанию okna-7dbf8).
#
# Временные демо-ссылки (preview-каналы вида https://<сайт>--demo-<хэш>.web.app)
# публикуются не этим скриптом, а командой hosting:channel:deploy — см. WEB-DEMO.md.
set -e
cd "$(dirname "$0")"

FIREBASE_BIN="${FIREBASE_BIN:-$(command -v firebase || echo "$HOME/.dsh/firebase-tools/node_modules/.bin/firebase")}"
FLUTTER_BIN="${FLUTTER_BIN:-$HOME/Downloads/flutter/bin/flutter}"
TARGET="${1:-excl}"
PROJECT="${PROJECT:-okna-7dbf8}"

echo "== 1/3 Сборка веб-версии =="
"$FLUTTER_BIN" pub get
"$FLUTTER_BIN" build web --release

echo "== 2/3 Админка и вход в Firebase =="
# Админка лежит отдельно от Flutter-сборки: кладём её в build/web/admin,
# иначе на сайте остаётся старая версия.
rm -rf build/web/admin
cp -R admin build/web/admin
"$FIREBASE_BIN" projects:list >/dev/null
echo "== 3/3 Публикация (target: $TARGET, проект: $PROJECT) =="
"$FIREBASE_BIN" deploy --only "hosting:$TARGET" --project "$PROJECT"

echo "Готово. Адреса: excl → https://myagkie-okna-excl.web.app, v1 → https://okna-7dbf8.web.app"
