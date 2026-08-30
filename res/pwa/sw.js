var CACHE = "{{{nonce}}}";
var PRECACHE = {{{precache}}};
var NO_CACHE = {{{no_cache}}};
var INDEX_HTML = {{{index_html}}};

function noCache (pathname) {
  for (var i = 0; i < NO_CACHE.length; i++)
    if (NO_CACHE[i].test(pathname)) return true;
  return false;
}

self.addEventListener("install", function (ev) {
  ev.waitUntil((async function () {
    var cache = await caches.open(CACHE);
    for (var i = 0; i < PRECACHE.length; i++) {
      var p = PRECACHE[i];
      if (noCache(p)) continue;
      var url = new URL(p, self.location.origin).href;
      var resp = await fetch(p, { cache: "reload" });
      if (!resp.ok) throw new Error("precache failed: " + p + " (" + resp.status + ")");
      await cache.put(url, resp);
    }
    if (!self.registration.active) await self.skipWaiting();
  })());
});

self.addEventListener("activate", function (ev) {
  ev.waitUntil((async function () {
    var keys = await caches.keys();
    await Promise.all(keys.filter(function (k) {
      return k !== CACHE;
    }).map(function (k) {
      return caches.delete(k);
    }));
    await self.clients.claim();
  })());
});

async function cacheFirst (req) {
  var cache = await caches.open(CACHE);
  var hit = await cache.match(req.url, { ignoreSearch: true, ignoreVary: true });
  if (hit) return hit;
  var resp;
  try {
    resp = await fetch(req);
  } catch (e) {
    return new Response("", { status: 503, statusText: "offline" });
  }
  if (resp.ok) await cache.put(req.url, resp.clone());
  return resp;
}

self.addEventListener("fetch", function (ev) {
  var req = ev.request;
  if (req.method !== "GET") return;
  var url = new URL(req.url);
  if (url.origin !== self.location.origin) return;
  if (INDEX_HTML !== null && url.pathname === "/") {
    ev.respondWith(new Response(INDEX_HTML, {
      headers: { "Content-Type": "text/html; charset=utf-8" }
    }));
    return;
  }
  if (noCache(url.pathname)) return;
  ev.respondWith(cacheFirst(req));
});

self.addEventListener("message", function (ev) {
  if (ev.data && ev.data.type === "skip_waiting") self.skipWaiting();
});
