const CACHE = 'okna-pwa-v3';
const SHELL = [
  '/pwa/',
  '/pwa/index.html',
  '/pwa/style.css',
  '/pwa/app.js',
  '/pwa/manifest.webmanifest',
  '/icons/Icon-192.png',
  '/icons/Icon-512.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(SHELL)));
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((key) => key !== CACHE).map((key) => caches.delete(key)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET' || new URL(request.url).origin !== location.origin) return;
  const isPage = request.mode === 'navigate' || request.url.endsWith('/pwa/') || request.url.endsWith('/pwa/index.html');
  if (isPage) {
    event.respondWith(
      fetch(request).then((response) => {
        const copy = response.clone();
        caches.open(CACHE).then((cache) => cache.put('/pwa/index.html', copy)).catch(() => {});
        return response;
      }).catch(() => caches.match('/pwa/index.html'))
    );
    return;
  }
  event.respondWith(
    caches.match(request).then((cached) => {
      if (cached) return cached;
      return fetch(request).then((response) => {
        const copy = response.clone();
        caches.open(CACHE).then((cache) => cache.put(request, copy)).catch(() => {});
        return response;
      }).catch(() => caches.match('/pwa/index.html'));
    })
  );
});
