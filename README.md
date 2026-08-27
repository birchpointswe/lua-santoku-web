<p align="center">
  <img src="https://santoku.dev/logo-santoku-web.png" height="64" alt="santoku-web">
</p>

# santoku-web

Lua for the browser. A Lua-to-JavaScript marshaling layer compiled to WebAssembly with
Emscripten, plus everything built on it: DOM manipulation through a batched command
buffer, promises and async/await, fetch, WebSockets, web workers over RPC, OPFS-backed
SQLite, and PWA scaffolding (index page, manifest, service worker, CSP).

## Install

```sh
luarocks install santoku-web
```

## Example

```lua
local js = require("santoku.web.js")
local dom = require("santoku.web.dom")

dom.listen("save", "click", function ()
  dom.text("status", "saving")
  dom.class_add("status", "busy")
  dom.flush()
  js.console:log("clicked")
end)
```

DOM writes queue into a command buffer and cross into JavaScript once, on `flush`. Every
JavaScript value that reaches Lua is a handle you can index, call, and pass back, so
there is no separate JS file to keep in sync.

## Documentation

Runnable examples and the full API: [santoku.dev](https://santoku.dev/#santoku-web).

For agents and LLM tooling: [llms.txt](https://santoku.dev/llms.txt) for the index,
[llms-full.txt](https://santoku.dev/llms-full.txt) for every documented example.

## Tests

The browser-runtime tests live under [`test/spec/santoku/web`](test/spec/santoku/web) and
run with `toku test --wasm`: [`val.wasm.lua`](test/spec/santoku/web/val.wasm.lua),
[`js.wasm.lua`](test/spec/santoku/web/js.wasm.lua),
[`dom.wasm.lua`](test/spec/santoku/web/dom.wasm.lua),
[`async.wasm.lua`](test/spec/santoku/web/async.wasm.lua),
[`await.wasm.lua`](test/spec/santoku/web/await.wasm.lua), and the memory and garbage
collection suites beside them.

## License

MIT, see [LICENSE](LICENSE).

## More examples

```lua
local test = require("santoku.test")

local err = require("santoku.error")
local assert = err.assert

local validate = require("santoku.validate")
local eq = validate.isequal

local csp = require("santoku.web.pwa.csp")
local version = require("santoku.web.version")

local function has (haystack, needle)
  return string.find(haystack, needle, 1, true) ~= nil
end

test("hash the inline scripts of a page, skipping external ones", function ()
  local hashes = csp.script_hashes([[
    <script src="/app.js"></script>
    <script>var a = 1</script>
    <script>var a = 1</script>
    <script>var b = 2</script>
  ]])
  assert(eq(2, #hashes))
  assert(eq("sha256-", string.sub(hashes[1], 1, 7)))
end)

test("build a policy that allows exactly those scripts", function ()
  local policy = csp.policy({ "sha256-abc" })
  assert(eq(true, has(policy, "script-src 'self' 'wasm-unsafe-eval' 'sha256-abc'")))
  assert(eq(true, has(policy, "object-src 'none'")))
end)

test("individual directives can be widened", function ()
  local policy = csp.policy({}, { connect = "'self' https://api.example.com" })
  assert(eq(true, has(policy, "connect-src 'self' https://api.example.com")))
  assert(eq(true, has(csp.meta({}), 'http-equiv="Content-Security-Policy"')))
end)

test("the client version rides along on outgoing request headers", function ()
  version.set("1.2.3")
  assert(eq("1.2.3", version.get()))
  assert(eq("1.2.3", version.attach({})["X-Client-Version"]))
end)
```
