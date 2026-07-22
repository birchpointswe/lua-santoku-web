local js = require("santoku.web.js")
local val = require("santoku.web.val")
local sqlite = require("santoku.web.sqlite")
local coop = require("santoku.web.sqlite.coop")
local rpc = require("santoku.web.rpc")
local async = require("santoku.web.async")

local global = js.self
local Module = global.Module

return function (db_path, opts, handler)
  if type(opts) == "function" then
    handler = opts
    opts = nil
  end

  local verbose = opts and opts.verbose
  if verbose then print("[sqlite-worker] function called, db_path:", db_path) end

  local rpc_handler = nil
  local pending = {}
  local draining = false
  local release_pending = false

  local function end_busy ()
    js.globalThis.__tk_coop_busy = false
    if release_pending and #pending == 0 then
      release_pending = false
      js.globalThis:__tk_coop_release()
    else
      js.globalThis:__tk_coop_maybe_release()
    end
  end

  local function drain ()
    if draining or not rpc_handler then return end
    draining = true
    async(function ()
      while #pending > 0 do
        coop.acquire()
        local ev = table.remove(pending, 1)
        local ok, e = pcall(rpc_handler, ev)
        if not ok then
          print("[sqlite-worker] dispatch error: " .. tostring(e))
        end
        end_busy()
      end
      draining = false
    end)
  end

  Module.on_message = function (_, ev)
    if ev.data and ev.data.type == "coop_release" then
      if draining or js.globalThis.__tk_coop_busy then
        release_pending = true
      else
        js.globalThis:__tk_coop_release()
      end
      return
    end
    if ev.data and ev.data.REGISTER_PORT then
      if verbose then print("[sqlite-worker] REGISTER_PORT received") end
      local port = ev.data.REGISTER_PORT
      port:addEventListener("message", function (_, port_ev)
        if port_ev.data and port_ev.data.type == "ping" then
          local pong_port = port_ev.ports and port_ev.ports[1]
          if pong_port then
            if verbose then print("[sqlite-worker] ping received, sending pong") end
            pong_port:postMessage(val({ type = "pong" }, true))
          end
          return
        end
        if verbose then print("[sqlite-worker] port message received:", port_ev.data and port_ev.data[1]) end
        pending[#pending + 1] = port_ev
        drain()
      end)
      port:start()
      if verbose then print("[sqlite-worker] Sending port_ready through port") end
      port:postMessage(val({ type = "port_ready" }, true))
    end
  end
  if verbose then print("[sqlite-worker] message handler set up early") end
  Module:start()
  if verbose then print("[sqlite-worker] Module:start() complete") end

  async(function ()
    if verbose then print("[sqlite-worker] async block started") end
    if verbose then print("[sqlite-worker] starting sqlite.open") end
    js.globalThis.__tk_coop_busy = true
    local ok, db = sqlite.open(db_path, opts)
    if not ok then
      end_busy()
      print("[sqlite-worker] db_error: " .. tostring(db))
      global:postMessage(val({ type = "db_error", error = tostring(db) }, true))
      return
    end
    local handler_ok, ok2, handlers = pcall(handler, ok, db)
    if not handler_ok then
      end_busy()
      print("[sqlite-worker] db_error: handler error: " .. tostring(ok2))
      global:postMessage(val({ type = "db_error", error = "handler error: " .. tostring(ok2) }, true))
      return
    end
    if not ok2 then
      end_busy()
      print("[sqlite-worker] db_error: handler returned false: " .. tostring(handlers))
      global:postMessage(val({ type = "db_error", error = "handler returned false: " .. tostring(handlers) }, true))
      return
    end
    if verbose then print("[sqlite-worker] calling rpc.server") end
    rpc_handler = rpc.server(handlers)
    end_busy()
    drain()
    if verbose then print("[sqlite-worker] worker fully initialized, signaling worker_ready") end
    global:postMessage(val({ type = "worker_ready" }, true))
  end)
end
