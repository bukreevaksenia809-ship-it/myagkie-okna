#!/usr/bin/env bash
# Сборка веб-версии и публикация на Firebase Hosting.
# Перед первым запуском: firebase login и указать проект в .firebaserc
# (или передать его аргументом: ./deploy-web.sh my-project-id).
set -e
cd "$(dirname "$0")"

FIREBASE_BIN="${FIREBASE_BIN:-$(command -v firebase || echo "$HOME/.dsh/firebase-tools/node_modules/.bin/firebase")}"
FLUTTER_BIN="${FLUTTER_BIN:-$HOME/Downloads/flutter/bin/flutter}"

echo "== 1/3 Сборка веб-версии =="
"$FLUTTER_BIN" pub get
"$FLUTTER_BIN" build web --release

echo "== 2/3 Проверка входа в Firebase =="
"$FIREBASE_BIN" projects:list >/dev/null

echo "== 3/3 Публикация =="
if [ -n "$1" ]; then
  "$FIREBASE_BIN" deploy --only hosting --project "$1"
else
  "$FIREBASE_BIN" deploy --only hosting
fi

echo "Готово. Адрес смотрите в выводе выше (https://<проект>.web.app)"
