# Веб-версия: демонстрационные ссылки

Проект Firebase: **okna-7dbf8**. В нём два сайта (Hosting sites) — по одному на
каждую зафиксированную версию приложения. Сборки не мешают друг другу: у
каждой версии свой сайт и свой канал `demo`.

| Версия | Демо-ссылка (preview-канал) | Сайт | Живёт до |
|---|---|---|---|
| **Мягкие окна Excl** (текущая) | https://myagkie-okna-excl--demo-ysodwqfm.web.app | `myagkie-okna-excl` | **13 ноября 2026, 23:00** |
| **Мягкие окна 1** (зафиксирована) | https://okna-7dbf8--demo-yuif0q4a.web.app | `okna-7dbf8` | 13 ноября 2026, 15:10 |

Что за ссылки:

- **Excl** — текущая разработка (git-ветка `main`, версия 2.0.0). Пересобирается
  и переопубликовывается сколько угодно раз: адрес канала при этом не меняется.
- **Мягкие окна 1** — зафиксированная первая версия (git-тег `myagkie-okna-1`,
  архивы в `versions/Мягкие окна 1/`). Эта ссылка **не перезаписывается**
  сборками Excl и остаётся как демонстрация первой версии.

Оба адреса — временные preview-каналы (`demo`), они сами исчезают в указанную
дату. Боевые (постоянные) адреса сайтов сейчас пусты и отдают 404 «Site Not
Found»: `https://myagkie-okna-excl.web.app` и `https://okna-7dbf8.web.app`.
Это сделано намеренно, чтобы демо не осталось в публичном доступе навсегда.

## Прямые ссылки на вкладки (Excl)

- чертёж — https://myagkie-okna-excl--demo-ysodwqfm.web.app/
- раскладка на рулоне — `?tab=roll`
- расходы — `?tab=costs`

## Как пересобрать и переопубликовать ссылку Excl

```bash
cd soft_window_drawer
export PATH="$HOME/Downloads/flutter/bin:$PATH"
FB=/Users/davidovjr7/.dsh/firebase-tools/node_modules/.bin/firebase

flutter pub get
flutter build web --release --pwa-strategy=none      # папка build/web

# канал demo на сайте Excl; --only принимает ИМЯ ЦЕЛИ (excl / v1),
# БЕЗ префикса hosting: — команда добавляет его сама
"$FB" hosting:channel:deploy demo --expires 30d --only excl --project okna-7dbf8
```

Команда печатает адрес канала (`https://myagkie-okna-excl--demo-<хэш>.web.app`)
и дату окончания. Хэш в адресе не меняется при повторных публикациях.

Важно: `--only hosting:excl` для `hosting:channel:deploy` **не работает** —
CLI сам подставляет префикс `hosting:` и получается `hosting:hosting:excl`
(ошибка «Hosting site or target ... not detected in firebase.json»). Для
`firebase deploy` (боевая публикация), наоборот, нужен полный вид
`--only hosting:excl`.

### Продлить срок

Повторная публикация канала с новым `--expires` обновляет срок:

```bash
"$FB" hosting:channel:deploy demo --expires 30d --only excl --project okna-7dbf8
```

Максимум — 30 дней (`30d`), также принимаются `12h`, `7d`.

### Посмотреть каналы

```bash
"$FB" hosting:channel:list --site myagkie-okna-excl --project okna-7dbf8
"$FB" hosting:channel:list --site okna-7dbf8 --project okna-7dbf8
```

### Удалить канал досрочно

```bash
"$FB" hosting:channel:delete demo --site myagkie-okna-excl --project okna-7dbf8
```

## Боевая (постоянная) публикация

Публикует сборку из `build/web` на постоянный адрес **своего** сайта:

```bash
./deploy-web.sh excl     # → https://myagkie-okna-excl.web.app (Мягкие окна Excl)
./deploy-web.sh v1       # → https://okna-7dbf8.web.app        (Мягкие окна 1)
```

Скрипт берёт цель хостинга из `firebase.json`, а соответствие «цель → сайт» —
из `.firebaserc`:

| Цель (target) | Сайт (site) | Что там |
|---|---|---|
| `v1` | `okna-7dbf8` | «Мягкие окна 1» |
| `excl` | `myagkie-okna-excl` | «Мягкие окна Excl» |

Обратите внимание: `firebase deploy --only hosting` без цели публикует
**оба** сайта одной и той же сборкой. Чтобы не перезаписать демо версии 1,
всегда указывайте цель (`hosting:v1` или `hosting:excl`).

## Что уже проверено (curl, 14 октября 2026)

```
$ curl -s -o /dev/null -w "%{http_code}" https://myagkie-okna-excl--demo-ysodwqfm.web.app/
200
$ curl -s https://myagkie-okna-excl--demo-ysodwqfm.web.app/ | grep -o "<title>.*</title>"
<title>Мягкие окна Excl</title>
$ curl -s https://myagkie-okna-excl--demo-ysodwqfm.web.app/main.dart.js | shasum -a 256
f327e85f00357000bfffead2223d786fe95380bbd2ea9a33b761453fea5e1789  (3 922 229 байт — совпадает с локальной сборкой)
```

Старая ссылка версии 1 тоже проверена: `https://okna-7dbf8--demo-yuif0q4a.web.app/`
отдаёт 200 и заголовок `<title>Мягкие окна</title>` — её мы не трогали.

## Вариант без интернета: локальная сеть

```bash
cd soft_window_drawer
./serve-demo.sh          # соберёт при необходимости и напечатает ссылку
```

Сервер отдаёт файлы со сжатием gzip — бандл едет ~1 МБ вместо 3,9 МБ.
Минус: работает, только пока включён этот компьютер и запущен сервер.

### Почему не получилось через бесплатные туннели

Пробовали два сервиса без аккаунта, оба не прошли через этого провайдера:

- Cloudflare quick tunnel (`cloudflared tunnel --url`) — соединение
  регистрируется, но публичный адрес отдаёт **530** (ошибка туннеля);
- SSH-туннель `localhost.run` — ссылка открывается, но **большие файлы
  обрываются** (вместо 3,9 МБ приходит 24 КБ) и сессия падает.

Поэтому для ссылки «из другого города» нужен нормальный хостинг — Firebase
Hosting (выше) или любой другой по токену (Netlify, Cloudflare Pages).

## Отличия веб-версии от десктопной

| Что | macOS / Windows | Браузер |
|---|---|---|
| Сохранить PDF | файл в `~/Downloads/Мягкие окна` | браузер скачивает файл |
| Печать | системный диалог печати | диалог печати браузера |
| Заказы | JSON-файлы в `~/Downloads/Мягкие окна/Заказы` | локальное хранилище браузера (localStorage) |
| Раскладка/чертежи | всё так же | всё так же |

## Если нужен вход в Firebase без браузера

```bash
firebase login:ci          # напечатает токен
firebase deploy --only hosting:excl --project okna-7dbf8 --token <токен>
```

## История

- Первая версия («Мягкие окна 1») публиковалась как сайт `okna-7dbf8`
  (канал `demo`, ссылка `https://okna-7dbf8--demo-yuif0q4a.web.app`).
- Версия Excl публикуется на **отдельном** сайте `myagkie-okna-excl`
  (канал `demo`, ссылка `https://myagkie-okna-excl--demo-ysodwqfm.web.app`),
  чтобы сборки новой версии не затирали демонстрацию первой.
