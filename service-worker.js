const CACHE_NAME = 'dashboard-vila-fit-v4';
const APP_SHELL = [
  './painel-atual.html',
  './manifest.json',
  './correcoes-painel.js',
  './icon-192.png',
  './icon-512.png',
  './icon-maskable-512.png'
];

self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE_NAME).then(cache => cache.addAll(APP_SHELL)));
  self.skipWaiting();
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys => Promise.all(
      keys.filter(key => key !== CACHE_NAME).map(key => caches.delete(key))
    ))
  );
  self.clients.claim();
});

self.addEventListener('fetch', event => {
  if (event.request.mode === 'navigate') {
    event.respondWith(
      fetch(event.request, { cache: 'no-store' }).then(response => {
        const copia = response.clone();
        caches.open(CACHE_NAME).then(cache => cache.put('./painel-atual.html', copia));
        return response;
      }).catch(() => caches.match('./painel-atual.html'))
    );
    return;
  }
  if (new URL(event.request.url).pathname.endsWith('/correcoes-painel.js')) {
    event.respondWith(
      fetch(event.request, { cache: 'no-store' }).then(response => {
        const copia = response.clone();
        caches.open(CACHE_NAME).then(cache => cache.put(event.request, copia));
        return response;
      }).catch(() => caches.match(event.request))
    );
    return;
  }
  event.respondWith(
    caches.match(event.request).then(cached => cached || fetch(event.request))
  );
});
