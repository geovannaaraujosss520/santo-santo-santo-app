/* Santo Santo Santo · service worker
   - página: busca sempre a versão mais nova na internet; sem internet, abre a última salva
   - ícones e manifesto: guardados no aparelho
   - dados do Supabase, login e verificação humana: nunca passam por aqui */
const VERSAO = 'sss-2026-10-28-2';
const ESTATICOS = [
  './', './index.html', './manifest.webmanifest',
  './icons/icon-192.png', './icons/icon-512.png', './icons/maskable-512.png',
  './icons/apple-touch-icon.png', './icons/favicon.png'
];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(VERSAO).then(c => c.addAll(ESTATICOS)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(chaves => Promise.all(chaves.filter(k => k !== VERSAO).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;

  if (req.mode === 'navigate') {
    e.respondWith(
      fetch(req)
        .then(resp => {
          if (resp.ok) { const copia = resp.clone(); caches.open(VERSAO).then(c => c.put('./index.html', copia)); }
          return resp;
        })
        .catch(() => caches.match('./index.html'))
    );
    return;
  }

  e.respondWith(caches.match(req).then(salvo => salvo || fetch(req)));
});
