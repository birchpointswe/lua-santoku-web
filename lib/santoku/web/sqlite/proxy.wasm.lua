local arr = require("santoku.array")
local js = require("santoku.web.js")
local util = require("santoku.web.util")
local val = require("santoku.web.val")
local rpc = require("santoku.web.rpc")

local document = js.document
local MessageChannel = js.MessageChannel
local Worker = js.Worker

local function init_worker (bundle_path)
  local w = Worker:new(bundle_path)
  local ch = MessageChannel:new()
  rpc.register_port(w, ch.port2)
  return ch.port1, w
end

return function (bundle_path, opts)
  opts = opts or {}
  local verbose = opts.verbose

  local function report_db_error (e)
    if document and document.body then
      document.body.classList:add("db-error")
      document.body:dispatchEvent(js.CustomEvent:new("db-error", {
        detail = { error = e }
      }))
    end
  end

  if verbose then
    print("[proxy] Spawning database worker")
  end

  local port, worker = init_worker(bundle_path)

  local core = setmetatable({}, {
    __index = function (_, k)
      return function (...)
        local ok, result = rpc.call(port, k, ...):await()
        if not ok then error(result) end
        if type(result) ~= "userdata" then return result end
        local n = result.length
        return arr.spread(val.lua(result, true), 1, n)
      end
    end
  })

  return core, util.promise(function (complete)
    worker.onmessage = function (_, ev)
      if ev.data and ev.data.type == "db_error" then
        if verbose then
          print("[proxy] Worker reported db_error:", ev.data.error)
        end
        report_db_error(ev.data.error)
      elseif ev.data and ev.data.type == "worker_ready" then
        if verbose then
          print("[proxy] Worker signaled ready")
        end
        if opts.on_worker_connection then opts.on_worker_connection() end
        complete(true)
      end
    end
    worker.onerror = function (_, ev)
      if verbose then
        print("[proxy] Worker error:", ev and ev.message)
      end
      report_db_error(ev and ev.message or "worker crashed")
    end
  end)
end
