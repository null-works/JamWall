const CACHE_NAME = 'jw-v3';
const ASSETS = [
    '/',
    '/index.html',
    '/manifest.json'
];

self.addEventListener('install', e => {
    e.waitUntil(
        caches.open(CACHE_NAME).then(cache => cache.addAll(ASSETS))
    );
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
    // Network-first for API calls
    if (e.request.url.includes('/api/')) {
        e.respondWith(
            fetch(e.request).catch(() =>
                new Response(JSON.stringify({ error: 'Offline' }), {
                    headers: { 'Content-Type': 'application/json' }
                })
            )
        );
        return;
    }
    
    // Cache-first for static assets
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
