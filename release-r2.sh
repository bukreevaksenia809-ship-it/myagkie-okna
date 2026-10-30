#!/usr/bin/env bash
# Публикация готовых сборок в Cloudflare R2.
#
# Требуется авторизация wrangler:
#   cd cloudflare && npx wrangler login
# Затем:
#   ./release-r2.sh 2.0.0
#
# Скрипт НЕ публикует метаданные обновления в Firestore — это делается в
# админке (вкладка «Обновление») или через saveRelease в admin/app.js.
set -euo pipefail
VERSION="${1:-2.0.0}"
BUCKET="${R2_BUCKET:-okna-updates}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

upload() {
  local file="$1" key="$2"
  if [ ! -f "$file" ]; then
    echo "· нет файла $file — пропускаю"
    return
  fi
  echo "↑ $file → $BUCKET/$key"
  npx --yes wrangler r2 object put "$BUCKET/$key" \
    --file "$file" --content-type "$(file --brief --mime-type "$file" 2>/dev/null || echo application/octet-stream)" \
    --remote
}

upload "dist/MyagkieOknaExcl-windows.zip" "releases/$VERSION/MyagkieOknaExcl-windows.zip"
upload "dist/MyagkieOknaExcl-macos.dmg" "releases/$VERSION/MyagkieOknaExcl-macos.dmg"
upload "build/app/outputs/flutter-apk/app-release.apk" "releases/$VERSION/MyagkieOknaExcl-android.apk"
upload "build/app/outputs/bundle/release/app-release.aab" "releases/$VERSION/MyagkieOknaExcl-android.aab"
upload "dist/MyagkieOknaExcl-web.zip" "releases/$VERSION/MyagkieOknaExcl-web.zip"

cat <<TXT

Готово. Проверьте ссылки:
  https://pub-0f1422253d90493ebf4b3a585b198489.r2.dev/releases/$VERSION/MyagkieOknaExcl-windows.zip
  https://pub-0f1422253d90493ebf4b3a585b198489.r2.dev/releases/$VERSION/MyagkieOknaExcl-macos.dmg
  https://pub-0f1422253d90493ebf4b3a585b198489.r2.dev/releases/$VERSION/MyagkieOknaExcl-android.apk

Осталось опубликовать метаданные в админке: версия $VERSION и эти ссылки.
TXT
