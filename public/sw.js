const CACHE_NAME = 'jw-v10';

self.addEventListener('install', e => {
    self.skipWaiting();
});

self.addEventListener('activate', e => {
    e.waitUntil(
        caches.keys().then(keys =>
            Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)))
        )
    );
    self.clients.claim();
});

self.addEventListener('fetch', e => {
    const url = new URL(e.request.url);

    // Network-first for API, audio, and HTML (the app itself)
    // Only cache-first for truly static assets (fonts, icons, manifest)
    if (e.request.url.includes('/api/') || e.request.url.includes('/audio/') ||
        e.request.mode === 'navigate' || url.pathname.endsWith('.html') || url.pathname === '/') {
        e.respondWith(
            fetch(e.request).then(res => {
                const clone = res.clone();
                caches.open(CACHE_NAME).then(cache => cache.put(e.request, clone));
                return res;
            }).catch(() =>
                caches.match(e.request).then(cached =>
                    cached || new Response('Offline', { status: 503 })
                )
            )
        );
        return;
    }

    // Cache-first only for static assets (icons, manifest, fonts)
    e.respondWith(
        caches.match(e.request).then(cached =>
            cached || fetch(e.request).then(res => {
                const clone = res.clone();
                caches.open(CACHE_NAME).then(cache => cache.put(e.request, clone));
                return res;
            })
        )
    );
});
