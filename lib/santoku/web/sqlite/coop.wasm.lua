local js = require("santoku.web.js")









local M = {}

local last_gen = 0
local reacquire_handler = nil






M.on_reacquire = function (fn)
  reacquire_handler = fn
  last_gen = js.globalThis:__tk_coop_gen()
end

M.acquire = function ()
  while true do
    js.globalThis.__tk_coop_busy = true
    if js.globalThis:__tk_coop_held() then
      local gen = js.globalThis:__tk_coop_gen()
      if gen ~= last_gen then
        last_gen = gen
        if reacquire_handler then reacquire_handler() end
      end
      return
    end
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
