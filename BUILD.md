# Сборка и выпуск приложения

Приложение называется **«Мягкие окна Excl»** (`MyagkieOknaExcl`), текущая
версия 2.0.0 (сборка 21). Иконка — мягкое окно: коричневая окантовка, плёнка, люверсы и
молния.

> Предыдущая версия **«Мягкие окна 1»** (приложение `MyagkieOkna`, версия 1.1.0)
> зафиксирована git-тегом `myagkie-okna-1`; её исходники и веб-сборка лежат в
> `versions/Мягкие окна 1/` (см. `versions/ЧИТАЙ-МЕНЯ.md`). Всё, что описано
> ниже, относится к версии **Excl** — дальнейшая разработка идёт в ней.

## macOS

На macOS собирается одной командой (нужен Flutter SDK и Xcode):

```bash
cd soft_window_drawer
export PATH="$HOME/Downloads/flutter/bin:$PATH"
flutter pub get
flutter build macos --release
```

Готовый бандл: `build/macos/Build/Products/Release/MyagkieOknaExcl.app`
(в Finder и Dock он показывается как «Мягкие окна Excl» — так задано в
`Info.plist`).

Упаковка в DMG:

```bash
mkdir -p dist/dmg
cp -R build/macos/Build/Products/Release/MyagkieOknaExcl.app dist/dmg/
ln -s /Applications dist/dmg/Applications
hdiutil create -volname "Мягкие окна Excl" -srcfolder dist/dmg -ov -format UDZO \
  dist/MyagkieOknaExcl-macos.dmg
```

Что уже сделано в проекте:

- иконка: `macos/Runner/Assets.xcassets/AppIcon.appiconset/*` (16…1024 px);
- имя и идентификатор: `macos/Runner/Configs/AppInfo.xcconfig`
  (`PRODUCT_NAME = MyagkieOknaExcl`, `PRODUCT_BUNDLE_IDENTIFIER = ru.myagkieokna.excl`);
- отображаемое имя «Мягкие окна Excl»: `macos/Runner/Info.plist`
  (`CFBundleName`, `CFBundleDisplayName`) и заголовок окна в
  `macos/Runner/MainFlutterWindow.swift`;
- версия берётся из `pubspec.yaml` (`version: 2.0.0+21`);
- права: запись в `~/Downloads` и печать (`macos/Runner/*.entitlements`).

### Подпись и Gatekeeper

Сборка не подписана сертификатом Apple Developer, поэтому при первом запуске
macOS скажет, что разработчик не проверен. Варианты:

1. Пользователь открывает приложение через «Пуск → правый клик → Открыть»
   (один раз, дальше запускается обычно).
2. Снять карантин после распаковки: `xattr -dr com.apple.quarantine MyagkieOknaExcl.app`.
3. Для чистой раздачи нужен сертификат Developer ID и нотаризация:
   ```bash
   codesign --deep --force --options runtime --sign "Developer ID Application: ..." MyagkieOknaExcl.app
   xcrun notarytool submit MyagkieOknaExcl-macos.zip --apple-id ... --team-id ... --password ... --wait
   xcrun stapler staple MyagkieOknaExcl.app
   ```

## Windows

**Flutter не умеет кросс-компиляцию**: собрать `.exe` для Windows можно только на
Windows (или в CI на windows-раннере). Всё для этого в проекте уже подготовлено.

Сборка на машине с Windows:

1. Установить Flutter SDK для Windows: https://docs.flutter.dev/get-started/install/windows
2. Установить Visual Studio 2022 с рабочей нагрузкой
   «Разработка классических приложений на C++» (Desktop development with C++).
3. Скачать папку проекта (или `git clone`) и выполнить:

```powershell
cd soft_window_drawer
flutter pub get
flutter build windows --release
```

Готовый комплект: `build\windows\x64\runner\Release\`
(внутри `MyagkieOknaExcl.exe`, `flutter_windows.dll`, `data\`). Эту папку целиком
нужно упаковать в zip и передавать пользователю — запускать `MyagkieOknaExcl.exe`.

Что уже подготовлено под Windows:

- платформа добавлена: папка `windows/`;
- иконка приложения: `windows/runner/resources/app_icon.ico`
  (16, 24, 32, 48, 64, 128, 256 px);
- имя и заголовок окна: `windows/runner/main.cpp`
  (`Мягкие окна Excl — чертежи, раскрой, раскладка`, файл в UTF-8 с BOM —
  не сохраняйте его без BOM, иначе заголовок поедет);
- свойства файла: `windows/runner/Runner.rc`
  (`ProductName`, `OriginalFilename`, `InternalName` — все с `Excl`);
- имя бинарника и идентификатор: `windows/CMakeLists.txt`
  (`BINARY_NAME = MyagkieOknaExcl`, `APPLICATION_ID = ru.myagkieokna.excl`).

## Выпуск 2.0.0 (уже сделан)

- GitHub Actions собирает Windows ZIP, macOS DMG/ZIP, Android APK/AAB и Web ZIP,
  тег `v2.0.0`; все файлы лежат в Releases публичного репозитория
  `bukreevaksenia809-ship-it/myagkie-okna`.
- Firestore `config/app` обновлён: `latestVersion = 2.0.0`, ссылки на GitHub
  Releases, SHA-256 Windows/macOS.
- Боевой веб: https://myagkie-okna-excl.web.app (Firebase Hosting, target `excl`).
- Админка кладётся в `build/web/admin` при `deploy-web.sh`; без этого шага на
  сайте остаётся старая версия.
- R2-зеркало: `./release-r2.sh 2.0.0` (требует живой сессии wrangler).

## Веб-версия и SQLite

Перед первой веб-сборкой (или после обновления пакета
`sqflite_common_ffi_web`) служебные файлы кладутся в `web/`:

```bash
dart run sqflite_common_ffi_web:setup
# создаёт web/sqlite3.wasm и web/sqflite_sw.js
```

Без них склад и заказы в браузере не откроются: это SQLite WASM и worker.
Оба файла уже в репозитории, `flutter build web` копирует их в `build/web`.

```bash
export PATH="$HOME/Downloads/flutter/bin:$PATH"
flutter build web --release --pwa-strategy=none   # результат в build/web
```

Публикация — на **отдельный сайт** Firebase Hosting `myagkie-okna-excl`
(цель `excl` в `firebase.json`/`.firebaserc`):

```bash
FB=/Users/davidovjr7/.dsh/firebase-tools/node_modules/.bin/firebase
"$FB" hosting:channel:deploy demo --expires 30d --only hosting:excl --project okna-7dbf8
# боевой (постоянный) адрес сайта:
./deploy-web.sh excl
```

Временная демо-ссылка версии Excl — в `WEB-DEMO.md`. Старая веб-ссылка
версии «Мягкие окна 1» живёт на сайте `okna-7dbf8` (цель `v1`) и не
перезаписывается сборками Excl.

## Готовый релиз версии 1 (уже выпущен)

Эти ссылки относятся к зафиксированной версии «Мягкие окна 1»:

- Релиз: https://github.com/kurwaHomik-cyber/myagkie-okna/releases/tag/v1.0.2
- Прямая ссылка на Windows-сборку:
  https://github.com/kurwaHomik-cyber/myagkie-okna/releases/download/v1.0.2/MyagkieOkna-windows.zip
- Репозиторий приватный, поэтому ссылки открываются под вашим аккаунтом:
  скачайте zip и передайте заказчику файлом (15 МБ).
- В релизе также лежат `MyagkieOkna-macos.dmg` и `MyagkieOkna-macos.zip`.

Новые релизы версии Excl выходят отдельными тегами (например `v2.0.0`) и
содержат файлы с приставкой `Excl` — см. следующий раздел.

Сделать репозиторий публичным (тогда ссылку можно отправлять кому угодно,
но исходники тоже станут открытыми):

```bash
gh repo edit kurwaHomik-cyber/myagkie-okna --visibility public --accept-visibility-change-consequences
```

## Выпуск через GitHub (сборка .exe без Windows-машины)

Windows-сборку делает сам GitHub — на виртуальной машине с Windows. Вам
не нужен ни Windows, ни Visual Studio, нужен только аккаунт GitHub.

### Как выпустить версию

1. Поднять версию в `pubspec.yaml` (например, `version: 2.0.1+6`) и
   `kAppVersion` в `lib/main.dart` — она видна в интерфейсе.
2. Закоммитить и поставить тег:

   ```bash
   git add -A
   git commit -m "Версия 2.0.1"
   git push origin main
   git tag v2.0.1
   git push origin v2.0.1
   ```

3. Открыть на GitHub вкладку **Actions** и дождаться зелёной галочки
   (5–8 минут). Затем раздел **Releases** — там появятся файлы:
   - `MyagkieOknaExcl-windows.zip` — портативная сборка для Windows
     (внутри `MyagkieOknaExcl.exe`, `data/`, `ЧИТАЙ-МЕНЯ.txt`);
   - `MyagkieOknaExcl-macos.dmg` и `MyagkieOknaExcl-macos.zip` — для macOS.

Ссылку на релиз (`https://github.com/<логин>/<репозиторий>/releases/latest`)
можно отправлять заказчику: ему не нужен ни Flutter, ни Python — только
распаковать архив.

### Без тега

Тег не обязателен: во вкладке **Actions** → «Сборка и релиз» →
**Run workflow** можно указать версию (например `2.0.1`) — релиз создастся
с тегом `v2.0.1`. Если оставить поле пустым, сборка просто положит архивы
в Artifacts, без релиза.

### Что именно делает workflow (`.github/workflows/build.yml`)

| Задача | Где | Что делает |
|---|---|---|
| Анализ и тесты | `ubuntu-latest` | `flutter analyze`, `flutter test` |
| Windows | `windows-latest` | `flutter build windows --release`, упаковка в zip, добавление `ЧИТАЙ-МЕНЯ.txt` |
| macOS | `macos-latest` | `flutter build macos --release`, ad-hoc подпись, DMG и zip |
| Релиз | оба | на тег `v*` или при указанной версии — `gh release create/upload` |

Важно: Windows собирается **только на Windows-раннере**. Кросс-компиляции
из macOS в Windows у Flutter нет, поэтому GitHub здесь — самый простой путь.

### Если репозиторий приватный

Готовые файлы из Releases видны только вам. Для заказчика либо сделайте
репозиторий публичным, либо скачайте zip и передайте файлом.

## Версия и имя в коде

- `pubspec.yaml` → `version: 2.0.0+21`, `name: soft_window_drawer`
  (имя Dart-пакета менять не нужно, оно не видно пользователю),
  `description: «Мягкие окна Excl: чертежи, раскрой и раскладка. ПВХ и скрин.»`;
- заголовок в приложении и в окне: «Мягкие окна Excl».
