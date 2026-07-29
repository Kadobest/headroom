// sw.js — makes Headroom installable and lets the app *shell* open
// without internet. Note: this does not make your data available
// offline — logging in, and any real project/client/invoice data
// still needs an internet connection to reach Supabase. This just
// means the app itself opens instantly instead of showing a browser
// "no connection" error.
//
// IMPORTANT: this uses a "network-first" strategy — it always tries
// to fetch the latest version of the app from the internet first,
// and only falls back to the saved offline copy if there's truly no
// connection. This avoids showing old, outdated content after an
// update (which is what "network-first" fixes, versus "cache-first"
// which can get stuck showing stale data).

const CACHE_NAME = "headroom-shell-v2"; // bumped version clears out the old stale cache
const SHELL_FILES = [
  "./",
  "./index.html",
  "./manifest.json",
  "./icon-192.png",
  "./icon-512.png",
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(SHELL_FILES))
  );
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((names) =>
      Promise.all(
        names.filter((n) => n !== CACHE_NAME).map((n) => caches.delete(n))
      )
    )
  );
  self.clients.claim();
});

self.addEventListener("fetch", (event) => {
  // Only handle same-origin requests for the app shell itself.
  // Everything else (Supabase, fonts, etc.) goes straight to the network.
  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin) return;

  event.respondWith(
    fetch(event.request)
      .then((response) => {
        const copy = response.clone();
        caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy));
        return response;
      })
      .catch(() => caches.match(event.request)) // offline fallback only
  );
});
