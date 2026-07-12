# santoku-web usage

Worked examples for the val/js/dom/async core, the part of the library covered by the
WASM test suite. Each section names its anchor test under `test/spec/santoku/web/`. Read
those for the full surface. The browser integrations (history, socket, util, rpc, sqlite,
pwa, trace) are documented at the module level in the [README](../README.md); they have no
local test anchor and are not covered here.

All of these run only in the WASM/browser runtime: they need a live JavaScript engine
(`globalThis`, `Promise`, `setTimeout`, and for the DOM section a `document`). Run them
through the `toku` WASM harness, not the plain Lua interpreter.

## The value boundary

`santoku.web.val` is the marshaling layer. Two views of the same JavaScript value exist:

- A **val userdata** wraps a handle and exposes an explicit method API.
- The **unwrapped view** (from `:lua()`, or `require("santoku.web.js").<Name>`) is the same
  object behind a metatable that forwards Lua index/newindex/call to JavaScript.

Conversion takes an optional `recurse` flag. Without it, objects and arrays stay live
proxies sharing one handle. With it, they deep-copy to plain Lua tables (JS to Lua) or
plain JS objects/arrays (Lua to JS).

## Marshaling Lua values to JS and back

Anchor: `val.wasm.lua`.

```lua
local val = require("santoku.web.val")

val("hello"):typeof():lua()   -- "string"
val(100.6):lua()              -- 100.6
val(true):lua()               -- true

-- a Lua table becomes a live JS proxy (one handle, mutations visible both ways)
local source = { a = 1, b = "2" }
local o = val(source)
o:set("c", 3)
-- source is updated too; o:lua() deep-reads back to { a = 1, b = "2", c = 3 }

-- recurse = true deep-copies instead of proxying
local arr = val({ { a = 1 }, { c = 3 } }, true):lua()
assert(arr[1].a == 1 and arr[2].c == 3)

-- a Lua function handed across is callable from JS; its return crosses back as a JS value
local fn = function (_, n) return n * n end
local sq = val(fn)
assert(sq:lua()(nil, 20) == 400)
```

Round-trip of binary data goes through `Uint8Array`. Anchor:
`uint8array.wasm.lua`.

```lua
local b = val.bytes("ABC")                 -- Lua string -> Uint8Array
assert(b:instanceof(val.global("Uint8Array")))
assert(b:str() == "ABC")                   -- Uint8Array -> Lua string
```

## Calling JavaScript

Anchor: `val.wasm.lua`, `js.wasm.lua`.

`val.global(name)` fetches a JS global as a val. From a val, `:get`/`:set` read and write
properties, `:call(this, ...)` invokes a function, `:new(...)` constructs. The unwrapped
view (`js.<Name>` or `:lua()`) lets you write the same calls with normal Lua syntax.

```lua
local val = require("santoku.web.val")
local js = require("santoku.web.js")

-- explicit form
local Math = val.global("Math")
assert(Math:get("max"):call(Math, 1, 2, 3):lua() == 3)

-- unwrapped form: js.<Name> == val.global("<Name>"):lua()
assert(js.Math:max(1, 2, 3) == 3)
assert(js.JSON:stringify({ a = { b = 1 } }) == "{\"a\":{\"b\":1}}")

-- construct and use
local m = js.Map:new()
m:set(1, 2)
assert(m:get(1) == 2)
assert(m:instanceof(js.Map))

-- deep object read with recurse
local o0, o1 = js.Object:new(), js.Object:new()
o0.o = o1
o1.a = 1
assert(o0:val():lua(true).o.a == 1)
```

## Building the DOM

Anchor: `dom.wasm.lua`.

`santoku.web.dom` batches mutations into a binary command buffer and applies them on
`flush()`. Each write names a target element by id. `read(...)` runs one or more queries
and returns their results in order. `listen(id, event, fn)` attaches an event handler
(`"window"` and `"body"` are accepted as ids).

```lua
local dom = require("santoku.web.dom")

-- queue writes, then apply in one batch
dom.text("a", "new text")
dom.attr("a", "title", "tip")     -- nil value removes the attribute
dom.style("a", "color", "blue")
dom.class_add("a", "active")
dom.html("container", "<p>hi</p>")
dom.insert_html("a", "afterend", '<div id="new1">inserted</div>')
dom.flush()

-- read queries: each table is { op, args... }; results return in order
local text, isdirty = dom.read(
  { "text", "a" },
  { "has_class", "a", "active" }
)

-- events
dom.listen("a", "click", function () dom.text("a", "clicked"); dom.flush() end)
```

Writes target elements by id; a write to a missing element fails on flush (see the "write
fail fast on missing element" case). `flush()` with no queued commands is a no-op.

## Awaiting promises

Anchor: `await.wasm.lua`, `async.wasm.lua`.

`santoku.web.async` runs a function inside a coroutine so promise resolution reads as
straight-line code. Inside an `async` block, `promise:await()` yields until the promise
settles and returns `ok, value`. `async(fn)` itself returns a JS promise, so blocks
compose and nest.

```lua
local js = require("santoku.web.js")
local async = require("santoku.web.async")
local Promise = js.Promise

async(function ()
  local ok, result = Promise:resolve(42):await()
  assert(ok == true and result == 42)

  local ok2, e = Promise:reject("error"):await()
  assert(ok2 == false and e == "error")
end)

-- async returns a promise; nest and await it
async(function ()
  local inner = async(function ()
    local _, v = Promise:resolve(21):await()
    return v * 2
  end)
  assert(inner:instanceof(Promise))
  local ok, result = inner:await()
  assert(ok and result == 42)
end)
```

The lower-level callback form also exists: `promise:await(function (_, ok, value) ... end)`
attaches a settlement handler without a coroutine. Anchor: the promise cases in
`async.wasm.lua` (`promise resolve`, `promise reject`, `promise rejection`).

## Defining a JavaScript class

Anchor: `class.wasm.lua`.

`val.class(config, parent)` builds a JS class. The config function runs with the class
prototype as `this` (received as its argument), so you assign methods to it; passing a
parent class extends it.

```lua
local val = require("santoku.web.val")

local Parent = val.class(function (proto)
  proto.fn_parent = function () return "parent" end
end)

local Child = val.class(function (proto)
  proto.fn_child = function () return "child" end
end, Parent)

Parent:new()
Child:new()
```

## Defining a web component

`santoku.web.util.component` wraps `val.class` to register a custom element. It is not
covered by a local test (custom elements need a DOM and a registry); it is exercised in
downstream applications. The shape, from `util.wasm.lua`:

```lua
local util = require("santoku.web.util")

local MyEl = util.component("my-el", {
  shadow = true,                  -- attach a closed shadow root
  style = "p { color: red }",     -- injected into the root
  html = "<p>hi</p>",
  connected = function (this, root) end,     -- connectedCallback
  disconnected = function (this, root) end,  -- disconnectedCallback
})
```

The build-time counterpart, `santoku.web.component` (`component.tk.lua`), compiles an HTML
component file (split into style/body/init/destroy by lpeg) into a JS custom-element
definition at build time. That is a `.tk.lua` template, not a runtime call.

## Gotchas

- **Booleans round-trip but watch typeof.** `val(true):lua()` is `true`; the val test
  carries a TODO noting boolean handling subtleties. Assert against `:typeof():lua()` when
  in doubt.
- **Array indices shift at the boundary.** Lua side is 1-indexed, JS side 0-indexed; the
  proxy converts. `a:get(0)` from Lua reads JS index 0, which is Lua element 1. See the
  "array proxy get/set adds 1 to numeric keys" cases in `val.wasm.lua`.
- **Proxy vs copy.** A non-recursed Lua table passed to JS is a live `Proxy`; reading it
  back with `:lua()` still sees Lua's 1-indexing. Use `recurse = true` when you need a
  detached plain value on the other side.
- **GC is observable.** Tests stop the collector, run, then force `collectgarbage` and the
  JS `gc()` and assert `val.IDX_REF_TBL.n` returns to its baseline. When you hold JS values
  in long-lived Lua state, that count stays elevated by design.
- **await needs an async context.** Calling `promise:await()` with no callback outside an
  `async` block raises "await called outside async context". Use the callback form, or wrap
  in `async(...)`.
