# Обновления через Cloudflare R2

## Что нужно

- аккаунт Cloudflare;
- включённый R2 (бесплатный тариф 10 ГБ, egress бесплатный);
- Node.js и `npx wrangler`.

## Первый запуск

```bash
cd cloudflare
npx wrangler login
npx wrangler r2 bucket create okna-updates
npx wrangler secret put ADMIN_PASSWORD
# введите пароль администратора (тот же, что для входа в админку)
npx wrangler deploy
```

Wrangler покажет адрес вида:

```
https://okna-updates.<account>.workers.dev
```

Скопируйте его в `admin/config.js`:

```js
uploadUrl: 'https://okna-updates.<account>.workers.dev',
```

Затем пересоберите/выложите админку.

## Проверка

```bash
curl https://okna-updates.<account>.workers.dev/health
```

Должно вернуть `{"ok":true,...}`.

## Загрузка

В админке → «Обновление» → выберите DMG/EXE/ZIP → «Загрузить в R2» → ссылка
подставится в поле URL → «Опубликовать».

Ограничение Worker — 100 МБ на файл. Для больших файлов нужен presigned URL
(следующий этап).


## Публикация готовых сборок версии 2.0

```bash
cd ..
./release-r2.sh 2.0.0
```

Скрипт загружает Windows ZIP, macOS DMG, Android APK/AAB и веб-архив в
`releases/2.0.0/`. Нужен `npx wrangler login`; срок токена проверяется
командой `npx wrangler whoami`.

После загрузки откройте админку → «Обновление», укажите версию `2.0.0`,
ссылки `https://pub-0f1422253d90493ebf4b3a585b198489.r2.dev/releases/2.0.0/…`
и нажмите «Опубликовать». Страница `web/updates/index.html` уже содержит эти
ссылки.
