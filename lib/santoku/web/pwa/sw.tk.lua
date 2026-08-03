local mustache = require("santoku.mustache")
local arr = require("santoku.array")
local template = mustache([[<% return readfile("res/pwa/sw.js") %>]]) -- luacheck: ignore

local function dq (s)
  return "\"" .. s .. "\""
end

local function sq (s)
  return "'" .. s:gsub("\\", "\\\\"):gsub("'", "\\'"):gsub("\n", "\\n"):gsub("\r", "\\r") .. "'"
end

return function (opts)
  local precache = {}
  for i, p in ipairs(opts.precache or {}) do
    precache[i] = dq(p:sub(1, 1) == "/" and p or ("/" .. p))
  end
  local no_cache = {}
  for i, p in ipairs(opts.no_cache or {}) do
    no_cache[i] = "new RegExp(" .. sq(p) .. ")"
  end
  return template({
    nonce = opts.nonce,
    precache = "[" .. arr.concat(precache, ",") .. "]",
    no_cache = "[" .. arr.concat(no_cache, ",") .. "]",
    index_html = opts.index_html and sq(opts.index_html) or "null",
  })
end
