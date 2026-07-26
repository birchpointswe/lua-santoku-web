local str = require("santoku.string")

local M = {}





function M.script_hashes (html)
  local hashes = {}
  local seen = {}
  for attrs, body in html:gmatch("<script(.-)>(.-)</script>") do
    if not attrs:find("src%s*=") then
      local h = "sha256-" .. str.to_base64(str.sha256(body))
      if not seen[h] then
        seen[h] = true
        hashes[#hashes + 1] = h
      end
    end
  end
  return hashes
end





function M.policy (hashes, opts)
  opts = opts or {}
  local script = "'self' 'wasm-unsafe-eval'"
  for i = 1, #hashes do
    script = script .. " '" .. hashes[i] .. "'"
  end
  local dirs = {
    "default-src " .. (opts.default or "'self'"),
    "script-src " .. script,
    "style-src " .. (opts.style or "'self' 'unsafe-inline'"),
    "img-src " .. (opts.img or "'self' data:"),
    "font-src " .. (opts.font or "'self'"),
    "connect-src " .. (opts.connect or "'self'"),
    "worker-src " .. (opts.worker or "'self'"),
    "manifest-src " .. (opts.manifest or "'self'"),
    "frame-src " .. (opts.frame or "'none'"),
    "object-src 'none'",
    "base-uri 'self'",
    "form-action " .. (opts.form or "'self'"),
  }
  return table.concat(dirs, "; ")
end


function M.meta (hashes, opts)
  return '<meta http-equiv="Content-Security-Policy" content="'
    .. M.policy(hashes, opts) .. '">'
end

return M
