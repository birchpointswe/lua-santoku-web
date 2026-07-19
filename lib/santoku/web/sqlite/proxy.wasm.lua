local arr = require("santoku.array")
local js = require("santoku.web.js")
local util = require("santoku.web.util")
local val = require("santoku.web.val")
local async = require("santoku.web.async")
local rpc = require("santoku.web.rpc")

local navigator = js.navigator
local document = js.document
local MessageChannel = js.MessageChannel
local BroadcastChannel = js.BroadcastChannel
local AbortController = js.AbortController
local Worker = js.Worker




local function init_port (port)
  local dead = false
  local waiters = {}
  local function kill ()
    if dead then return end
    dead = true
    local w = waiters
    waiters = {}
    for id in pairs(w) do w[id]() end
  end
  local proxy = setmetatable({}, {
    __index = function (_, k)
      return function (...)
        if dead then error("sqlite connection lost") end
        local call = rpc.call(port, k, ...)
        local id = {}
        local settled = false
        local raced = util.promise(function (complete)
          local function finish (ok, v)
            if settled then return end
            settled = true
            waiters[id] = nil
            complete(ok, v)
          end
          waiters[id] = function () finish(false, "sqlite connection lost") end
          call["then"]:call(call,
            function (_, v) finish(true, v) end,
            function (_, e) finish(false, e) end)
        end)
        local ok, result = raced:await()
        if not ok then error(result) end
        if type(result) ~= "userdata" then return result end
        local n = result.length
        return arr.spread(val.lua(result, true), 1, n)
      end
    end
  })
  return proxy, kill
end

local function init_worker (bundle_path)
  local w = Worker:new(bundle_path)
  local ch = MessageChannel:new()
  rpc.register_port(w, ch.port2)
  local proxy, kill = init_port(ch.port1)
  return proxy, kill, w
end

return function (bundle_path, opts)
  opts = opts or {}
  local verbose = opts.verbose

  local function log (...)
    if verbose then print("[proxy]", ...) end
  end

  local role = "none"
  local db = nil
  local db_kill = nil
  local worker = nil
  local client_id = nil
  local current_provider_port = nil
  local provider_counter = 0
  local lock_pending = false
  local lock_abort = nil
  local hold_release = nil
  local ready_resolver = nil
  local db_waiters = {}

  local broadcast_channel = BroadcastChannel:new("sqlite_shared_service")


  local become_provider, release_provider, drop_connection
  local request_provider_lock, request_provider_port
  local setup_worker_message_handler

  local function signal_db ()
    local w = db_waiters
    db_waiters = {}
    for i = 1, #w do w[i]() end
  end



  local function wait_for_db (ms)
    if db then return true end
    return util.promise(function (complete)
      local done = false
      local timer = util.set_timeout(function ()
        if not done then done = true; complete(true) end
      end, ms)
      arr.push(db_waiters, function ()
        if not done then done = true; util.clear_timeout(timer); complete(true) end
      end)
    end):await()
  end

  local function on_db_ready ()
    signal_db()
    if opts.on_worker_connection then opts.on_worker_connection() end
    if ready_resolver then
      ready_resolver()
      ready_resolver = nil
    end
  end

  local core = setmetatable({}, {
    __index = function (_, k)
      return function (...)
        if not db then
          wait_for_db(5000)
          if not db then error("sqlite worker not ready") end
        end
        return db[k](...)
      end
    end
  })

  local function get_client_id ()
    local nonce = "client_id_" .. tostring(math.random()):sub(3)
    local found_client_id = nil
    navigator.locks:request(nonce, function ()
      return async(function ()
        local ok, state = navigator.locks:query():await()
        if ok and state and state.held then
          local held = state.held
          for i = 1, held.length do
            local lock = held[i]
            if lock and lock.name == nonce then
              found_client_id = lock.clientId
              break
            end
          end
        end
        return true
      end)
    end):await()
    return found_client_id
  end

  local function hold_provider_lock ()
    return util.promise(function (complete)
      hold_release = function ()
        hold_release = nil
        complete(true)
      end
    end)
  end

  drop_connection = function ()
    if db_kill then db_kill(); db_kill = nil end
    db = nil
    if worker then worker:terminate(); worker = nil end
    if current_provider_port then current_provider_port:close(); current_provider_port = nil end
  end

  setup_worker_message_handler = function (w, on_ready)
    w.onmessage = function (_, ev)
      if ev.data and ev.data.type == "db_error" then
        log("Worker reported db_error:", ev.data.error)
        release_provider()
        if document and document.body then
          document.body.classList:add("db-error")
          document.body:dispatchEvent(js.CustomEvent:new("db-error", {
            detail = { error = ev.data.error }
          }))
        end
      elseif ev.data and ev.data.type == "worker_ready" then
        log("Worker signaled ready")
        if on_ready then on_ready() end
      end
    end
    w.onerror = function (_, ev)
      log("Worker error:", ev and ev.message)
      release_provider()
      if document and document.body then
        document.body.classList:add("db-error")
        document.body:dispatchEvent(js.CustomEvent:new("db-error", {
          detail = { error = ev and ev.message or "worker crashed" }
        }))
      end
    end
  end

  become_provider = function ()
    log("Becoming provider, clientId:", client_id)
    role = "provider"
    provider_counter = provider_counter + 1
    if current_provider_port then current_provider_port:close(); current_provider_port = nil end
    if db_kill then db_kill(); db_kill = nil end
    db, db_kill, worker = init_worker(bundle_path)
    setup_worker_message_handler(worker, function ()
      log("Announcing as provider")
      broadcast_channel:postMessage(val({ type = "provider", clientId = client_id }, true))
      on_db_ready()
    end)
  end

  release_provider = function ()
    if role ~= "provider" then
      if lock_pending and lock_abort then lock_abort:abort(); lock_pending = false end
      return
    end
    log("Releasing provider role")
    role = "none"
    drop_connection()
    broadcast_channel:postMessage(val({ type = "provider_gone", clientId = client_id }, true))
    if hold_release then hold_release() end
  end

  request_provider_lock = function ()
    if role == "provider" or lock_pending then return end
    if document.hidden then return end
    lock_pending = true
    lock_abort = AbortController:new()
    log("Requesting sqlite_db_access lock...")
    navigator.locks:request("sqlite_db_access",
      val({ signal = lock_abort.signal }, true),
      function ()
        lock_pending = false
        if document.hidden then
          log("Lock granted while hidden -- releasing, will retry when visible")
          return
        end
        become_provider()
        return hold_provider_lock()
      end):catch(function (_, e)
        lock_pending = false
        if e and e.name == "AbortError" then
          log("Lock request aborted (tab backgrounded)")
        else
          log("Lock request failed:", e)
        end
      end)
  end

  request_provider_port = function (counter)
    if counter ~= provider_counter then return end
    if role == "provider" or db then return end
    if not navigator.serviceWorker.controller then
      log("No SW controller yet, will retry")
      util.set_timeout(function () request_provider_port(counter) end, 500)
      return
    end

    local nonce = "req_" .. tostring(math.random()):sub(3)
    log("Requesting provider port with nonce:", nonce)

    local function on_sw_message (_, ev)
      if ev.data and ev.data.type == "db_port" and ev.data.nonce == nonce then
        navigator.serviceWorker:removeEventListener("message", on_sw_message)
        local port = ev.ports and ev.ports[1]
        if port and counter == provider_counter and role ~= "provider" and not db then
          log("Becoming consumer with port")
          current_provider_port = port
          role = "consumer"
          db, db_kill = init_port(port)
          on_db_ready()
        elseif port then
          port:close()
        end
      end
    end
    navigator.serviceWorker:addEventListener("message", on_sw_message)

    broadcast_channel:postMessage(val({ type = "request", nonce = nonce }, true))

    util.set_timeout(function ()
      if counter == provider_counter and not db and role ~= "provider" then
        local controller = navigator.serviceWorker.controller
        if controller then
          controller:postMessage(val({ type = "get_port", nonce = nonce }, true))
        end
      end
    end, 100)

    util.set_timeout(function ()
      if counter == provider_counter and not db and role ~= "provider" then
        log("Port request timeout, retrying...")
        navigator.serviceWorker:removeEventListener("message", on_sw_message)
        request_provider_port(counter)
      end
    end, 2000)
  end

  local function reconnect ()
    drop_connection()
    role = "none"
    provider_counter = provider_counter + 1
    request_provider_lock()
    request_provider_port(provider_counter)
  end

  broadcast_channel.onmessage = function (_, ev)
    local data = ev.data
    if not data then return end
    log("Received broadcast:", data.type, "clientId:", data.clientId)

    if data.type == "provider" then
      if data.clientId == client_id then return end
      if role == "provider" then return end
      reconnect()

    elseif data.type == "provider_gone" then
      if role == "provider" then return end
      reconnect()

    elseif data.type == "request" and role == "provider" and data.nonce then
      local controller = navigator.serviceWorker.controller
      if not controller then
        log("No SW controller, cannot send port")
        return
      end
      async(function ()
        local _, port = rpc.create_port(worker):await()
        controller:postMessage(
          val({ type = "store_port", nonce = data.nonce }, true),
          { port })
      end)
    end
  end

  return core, util.promise(function (complete)
    ready_resolver = function () complete(true) end

    async(function ()
      log("Waiting for SW ready...")
      local ok = navigator.serviceWorker.ready:await()
      if not ok then return end

      local cid = get_client_id()
      log("Got client ID:", cid)
      if not cid then return end
      client_id = cid



      navigator.locks:request(client_id, function ()
        return util.never()
      end):catch(function () end)

      request_provider_lock()
      request_provider_port(provider_counter)

      document:addEventListener("visibilitychange", function ()
        if document.hidden then
          if role == "provider" then
            release_provider()
          elseif lock_pending and lock_abort then
            lock_abort:abort()
            lock_pending = false
          end
        else
          request_provider_lock()
          if role ~= "provider" and not db then
            provider_counter = provider_counter + 1
            request_provider_port(provider_counter)
          end
        end
      end)

      js.window:addEventListener("pagehide", function ()
        release_provider()
      end)


      local fallback_delay = 5000 + math.floor(math.random() * 5000)
      util.set_timeout(function ()
        if db or role == "provider" or lock_pending then return end
        log("Fallback: still no db, re-requesting")
        request_provider_lock()
        provider_counter = provider_counter + 1
        request_provider_port(provider_counter)
      end, fallback_delay)
    end)
  end)
end
