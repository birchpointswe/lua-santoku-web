local mustache = require("santoku.mustache")
local tbl = require("santoku.table")
local lp = require("santoku.lpeg")
local csp = require("santoku.web.pwa.csp")
local err = require("santoku.error")
local template = mustache([[<% return readfile("res/pwa/index.html") %>]]) -- luacheck: ignore
local defaults = { charset = "utf-8", lang = "en" }
return function(opts)
  opts = tbl.merge({}, opts or {}, defaults)
  local out = template(opts)
  if opts.transforms then
    out = lp.transform_inline(out, opts.transforms)
    if opts.transforms.html then
      out = opts.transforms.html(out)
    end
  end
  if opts.csp then
    local meta = csp.meta(csp.script_hashes(out), opts.csp ~= true and opts.csp or nil)
    local injected, n = out:gsub("<head>", function () return "<head>\n" .. meta end, 1)
    if n ~= 1 then
      err.error("csp requested but no <head> found to inject the policy into")
    end
    out = injected
  end
  return out
end
