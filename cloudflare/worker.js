// Cloudflare Worker: загрузка обновлений в R2 и публичная раздача.
//
// POST /upload?name=file.dmg  (X-Admin-Password, body = файл)
//   -> { url, key, size }
// GET  /files/<key>          — скачивание файла
// GET  /health               — проверка
//
// Файлы лежат в R2, наружу отдаются через этот Worker. Egress у R2 бесплатный.
const MAX_BYTES = 100 * 1024 * 1024; // лимит тела запроса Worker

function allowedOrigin(request, env) {
  const origin = request.headers.get('Origin') || '';
  const allowed = (env.ALLOWED_ORIGINS || '')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean);
  if (allowed.includes('*')) return '*';
  if (allowed.includes(origin)) return origin;
  // Разрешаем локальную админку для отладки.
  if (origin.startsWith('http://localhost:') || origin.startsWith('http://127.0.0.1:')) {
    return origin;
  }
  return '';
}

function corsHeaders(request, env) {
  const origin = allowedOrigin(request, env);
  return {
    'Access-Control-Allow-Origin': origin || 'null',
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, X-Admin-Password',
    'Access-Control-Max-Age': '86400',
    Vary: 'Origin',
  };
}

function json(data, status, request, env, extra = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      ...corsHeaders(request, env),
      ...extra,
    },
  });
}

function safeName(raw) {
  const name = (raw || 'update.bin')
    .replace(/[\\/:*?"<>|]+/g, '-')
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-')
    .replace(/^\.+/, '')
    .slice(0, 120);
  return name || 'update.bin';
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders(request, env) });
    }

    if (url.pathname === '/health') {
      return json({ ok: true, service: 'okna-updates' }, 200, request, env);
    }

    if (url.pathname === '/upload' && request.method === 'POST') {
      if (!env.ADMIN_PASSWORD) {
        return json({ error: 'ADMIN_PASSWORD не задан' }, 500, request, env);
      }
      if (request.headers.get('X-Admin-Password') !== env.ADMIN_PASSWORD) {
        return json({ error: 'Неверный пароль загрузки' }, 401, request, env);
      }
      const length = Number(request.headers.get('Content-Length') || '0');
      if (length > MAX_BYTES) {
        return json({ error: 'Файл больше 100 МБ' }, 413, request, env);
      }
      const name = safeName(url.searchParams.get('name'));
      const key = `releases/${Date.now()}-${name}`;
      try {
        await env.UPDATES.put(key, request.body, {
          httpMetadata: {
            contentType:
              request.headers.get('Content-Type') || 'application/octet-stream',
            contentDisposition: `attachment; filename="${name}"`,
          },
        });
        const object = await env.UPDATES.head(key);
        return json(
          {
            url: `${url.origin}/files/${encodeURIComponent(key)}`,
            key,
            size: object?.size ?? length,
            name,
          },
          200,
          request,
          env,
        );
      } catch (error) {
        return json({ error: `Не удалось сохранить: ${error}` }, 500, request, env);
      }
    }

    if (url.pathname.startsWith('/files/') && request.method === 'GET') {
      const key = decodeURIComponent(url.pathname.slice('/files/'.length));
      if (!key || key.includes('..')) {
        return new Response('Not found', { status: 404, headers: corsHeaders(request, env) });
      }
      const object = await env.UPDATES.get(key);
      if (!object) {
        return new Response('Not found', { status: 404, headers: corsHeaders(request, env) });
      }
      const headers = new Headers();
      object.writeHttpMetadata(headers);
      headers.set('etag', object.httpEtag);
      headers.set('Cache-Control', 'public, max-age=3600');
      headers.set('Access-Control-Allow-Origin', allowedOrigin(request, env) || 'null');
      return new Response(object.body, { headers });
    }

    return json({ error: 'Not found' }, 404, request, env);
  },
};
