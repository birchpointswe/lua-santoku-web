# santoku-web

Lua for the browser: a Lua-to-JavaScript marshaling layer plus the web pieces built on
top of it (DOM, async/promises, fetch, WebSocket, web workers via RPC, OPFS SQLite, PWA
scaffolding). The code is compiled to WebAssembly with Emscripten and runs inside the
browser (or node, for the test harness). Built on base `santoku`, `santoku-mustache`,
`santoku-http`, `santoku-lpeg`, and `lua-cjson`.

This README is a usage guide, not an API reference. The tests are the spec: each module
points at the test that exercises its surface. Read those for the exhaustive list; read
this (and [`doc/usage.md`](doc/usage.md)) for how the layers fit together. For the
dependencies' own surface (string/table/error helpers, mustache rendering, the `http`
client, lpeg grammars), see their repositories; this doc does not re-document them.

## Three usage modes

santoku-web spans three distinct runtimes. A file's suffix tells you which one it belongs
to:

- `*.wasm.lua` / `*.wasm.c`: WASM/browser runtime. Compiled into the Emscripten module and
  run in the browser. The val/js/dom/async core and all the browser integrations live
  here.
- `*.tk.lua`: build-time toku template. Evaluated by the `toku` build harness (the `<% %>`
  blocks run at build time, reading sibling `res/` assets and minifying JS). Some emit a
  static artifact (an HTML page, a manifest, a web component definition); two of them
  (`dom.wasm.tk.lua`, `async.wasm.tk.lua`) carry both suffixes because they are build-time
  templates that emit a WASM-runtime module (the template inlines a `res/web/*.js` payload,
  the rest is ordinary runtime Lua).
- plain `.lua`: shared/native. No WASM gating, usable in a normal native Lua process
  (e.g. server-side version negotiation).

## Conventions

- **val is the boundary.** Every JavaScript value reaching Lua is a userdata wrapping a
  numeric handle into a JS-side handle table; every Lua value reaching JS is converted or
  proxied. `require("santoku.web.val")` is the one module that defines this; everything
  else is built on it.
- **Wrapped vs unwrapped.** A `val` userdata exposes the explicit method API (`:get`,
  `:set`, `:call`, `:new`, `:typeof`, `:instanceof`, `:lua`). Calling `:lua()` (or
  `require("santoku.web.js").<Name>`) gives you the same JS object behind a metatable that
  forwards index/newindex/call straight to JS, so you write `el.textContent`,
  `obj:method(a, b)`, `arr[1]`. The two views address the same underlying handle.
- **Recurse flag.** Conversion takes an optional `recurse` boolean. Without it, objects and
  arrays stay live JS proxies (one handle, mutations visible both ways). With it, they are
  deep-copied into plain Lua tables or plain JS objects/arrays.
- **Array index shift.** A JS array read or written through the Lua side is 1-indexed from
  Lua and 0-indexed from JS; the proxy adds or subtracts 1 so each side sees its own
  convention. Covered in `test/spec/santoku/web/uint8array.wasm.lua`.
- **GC across the boundary.** Lua values handed to JS are held by a registry ref and
  released by a JS `FinalizationRegistry`; JS values held by Lua are released on userdata
  `__gc`. The reference count is observable as `val.IDX_REF_TBL.n`, which the tests assert
  returns to baseline after collection.

## Module map

### WASM / browser runtime

| Module | Role | Anchor test |
|--------|------|-------------|
| `santoku.web.val` (C) | Lua-to-JS marshaling core: wrap/convert, get/set/call/new, class, bytes, the value metatables | `val.wasm.lua`, `class.wasm.lua`, `tostring.wasm.lua` |
| `santoku.web.js` | global accessor: `js.<Name>` is `val.global("<Name>"):lua()` | `js.wasm.lua` |
| `santoku.web.dom` | batched DOM writes/reads over a binary command buffer (`dom.buf` C), plus event `listen` | `dom.wasm.lua` |
| `santoku.web.async` | coroutine-based `async`/`await` over JS promises | `async.wasm.lua`, `await.wasm.lua` |
| `santoku.web.history` | hash-route history with distance-pruned marks | not test-anchored |
| `santoku.web.socket` | `fetch`/`request` wrappers returning normalized responses | not test-anchored |
| `santoku.web.util` | timers, throttle/debounce, `ws`, promise helpers, `component`, localStorage, fetch `Response` building | not test-anchored |
| `santoku.web.rpc` (C) | MessagePort RPC: `call` (client), `server` (worker handler), port setup | not test-anchored |
| `santoku.web.sqlite` | OPFS SAH-pool SQLite, returns a `santoku.sqlite` db | not test-anchored |
| `santoku.web.sqlite.worker` | worker-side SQLite RPC server | not test-anchored |
| `santoku.web.sqlite.proxy` | main-thread client proxy to the SQLite worker | not test-anchored |
| `santoku.web.pwa.sw` | service-worker factory (precache, fetch routing) | not test-anchored |

### Build-time toku templates (`.tk.lua`)

| Template | Emits | Mode |
|----------|-------|------|
| `santoku.web.component` | a custom-element JS definition from an HTML component file (lpeg-split into style/body/init/destroy) | build-time |
| `santoku.web.pwa.index` | the app's index HTML (mustache, optional lpeg transforms) | build-time |
| `santoku.web.pwa.manifest` | the PWA `manifest.json` (mustache) | build-time |
| `santoku.web.pwa.wrap_events` | a minified event-wrapping JS payload | build-time |
| `santoku.web.dom` | the `dom` runtime module (installs `res/web/dom.js` via the `dom.install` EM_JS module) | build-time -> runtime |
| `santoku.web.async` | the `async` runtime module (scheduler installed via the `asyncsched` EM_JS module) | build-time -> runtime |

### Shared / native (plain `.lua`)

| Module | Role |
|--------|------|
| `santoku.web.version` | client/server version negotiation (nginx-side check, browser-side header injection and mismatch hooks) |

## Canonical snippet

```lua
local val = require("santoku.web.val")
local js = require("santoku.web.js")

-- explicit val API: build a JS object, call a method, read the result
local obj = val.global("Object"):call(nil)   -- {}
obj:set("a", 1)
local one = obj:get("a")                       -- a val wrapping the number
assert(one:typeof():lua() == "number")
assert(one:lua() == 1)

-- unwrapped view: js.<Name> forwards straight to JavaScript
local json = js.JSON:stringify({ a = { b = 1 } })   -- "{\"a\":{\"b\":1}}"

-- a Lua function passed to JS is callable from JS; its return crosses back as a JS value
obj:set("square", function (_, n) return n * n end)
assert(obj:get("square"):call(obj, 20):lua() == 400)
```

Worked examples (val marshaling, calling JS, building DOM, awaiting promises, defining a
class and a component) live in [`doc/usage.md`](doc/usage.md).

## Building and testing

This repo uses the `toku` build harness. The C extensions (`val`, `dom/buf`, `rpc`) and the
`.wasm.lua` modules are compiled to WebAssembly with Emscripten. The tests under
`test/spec/santoku/web/` are all `*.wasm.lua`: they run in the WASM test harness (Emscripten
under node, driven by toku), not the normal Lua interpreter, because they require a live
JavaScript runtime (a `globalThis`, `Promise`, `setTimeout`, a `document` for the DOM test).
Run them through `toku` so the natives are built and the harness is in place. The 11 tests
cover the val/js/dom/async core (val, js, dom, async, await, class, memory, tostring,
uint8array, garbage, garbage-async); the browser integrations above marked "not
test-anchored" are exercised in downstream applications, not here.

Several modules pull in JS payloads from a sibling `res/` tree at build time (`res/web/*.js`,
`res/pwa/*`). Those assets are part of the build inputs, not the documented Lua surface.

## License

MIT License

Copyright 2025 Birch Point SWE

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
