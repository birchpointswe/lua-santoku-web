local js = require("santoku.web.js")









local M = {}

M.acquire = function ()
  while true do
    js.globalThis.__tk_coop_busy = true
    if js.globalThis:__tk_coop_held() then return end
    js.globalThis.__tk_coop_busy = false
    js.globalThis:__tk_coop_acquire():await()
  end
end

M.release = function ()
  js.globalThis.__tk_coop_busy = false
  js.globalThis:__tk_coop_maybe_release()
end

M.wrap = function (fn)
  M.acquire()
  local ok, e = pcall(fn)
  M.release()
  if not ok then error(e) end
end

return M
