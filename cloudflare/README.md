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
