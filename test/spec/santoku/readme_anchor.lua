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
