local arr = require("santoku.array")
local js = require("santoku.web.js")
local util = require("santoku.web.util")
local val = require("santoku.web.val")
local async = require("santoku.web.async")
local rpc = require("santoku.web.rpc")

local function is_provider_change (e)
  return type(e) == "string" and e:find("provider change", 1, true) ~= nil
end

local navigator = js.navigator
local document = js.document
local MessageChannel = js.MessageChannel
local BroadcastChannel = js.BroadcastChannel
local AbortController = js.AbortController
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

  local db = nil
  local worker
  local db_waiters = nil
  local invalidator = nil
  local invalidator_reject = nil

  local function arm_invalidator ()
    invalidator = util.promise(function (complete)
      invalidator_reject = function ()
        invalidator_reject = nil
        complete(false, "provider change")
      end
    end)
    invalidator:catch(function () end)
  end
  arm_invalidator()

  local function fire_invalidator ()
    if invalidator_reject then
      invalidator_reject()
    end
    arm_invalidator()
  end

  local function set_db (new_db)
    if db ~= new_db then
      if verbose then
        print("[proxy] set_db change (db:", db ~= nil, "-> new:", new_db ~= nil, "), firing invalidator")
      end
      fire_invalidator()
    end
    db = new_db
    if new_db and db_waiters then
      local ws = db_waiters
      db_waiters = nil
      for i = 1, #ws do ws[i]() end
    end
  end

  local function await_db ()
    return util.promise(function (complete)
      if db then
        complete(true, db)
        return
      end
      db_waiters = db_waiters or {}
      db_waiters[#db_waiters + 1] = function () complete(true, db) end
    end)
  end

  local core = setmetatable({}, {
    __index = function (_, k)
      return function (...)
        while true do
          local port = db
          if not port then
            if verbose then print("[proxy] core." .. tostring(k) .. ": no db, waiting") end
            await_db():await()
          else
            if verbose then print("[proxy] core." .. tostring(k) .. ": dispatching") end
            local inv = invalidator
            local call = rpc.call(port, k, ...)
            local ok, result = js.Promise:race(val({ call, inv }, true)):await()
            if ok then
              if verbose then print("[proxy] core." .. tostring(k) .. ": ok") end
              if type(result) ~= "userdata" then return result end
              local n = result.length
              return arr.spread(val.lua(result, true), 1, n)
            end
            if not is_provider_change(result) then
              if verbose then print("[proxy] core." .. tostring(k) .. ": error", result) end
              error(result)
            end
            if verbose then print("[proxy] core." .. tostring(k) .. ": provider change, retrying") end
          end
        end
      end
    end
  })
  local is_provider = false
  local client_id = nil
  local provider_counter = 0
  local current_provider_port = nil
  local ready_resolver = nil
  local lock_abort = nil
  local becoming_provider = false
  local lock_release_resolver = nil

  local function hold_lock ()
    return util.promise(function (complete)
      lock_release_resolver = function ()
        lock_release_resolver = nil
        complete(true)
      end
    end)
  end

  local broadcast_channel = BroadcastChannel:new("sqlite_shared_service")

  local function release_provider ()
    if lock_abort then
      lock_abort:abort()
      lock_abort = nil
    end
    becoming_provider = false
    if not is_provider then return end
    if verbose then
      print("[proxy] Releasing provider role (tab backgrounded)")
    end
    is_provider = false
    if worker then
      worker:terminate()
      worker = nil
    end
    set_db(nil)
    if lock_release_resolver then
      if verbose then
        print("[proxy] Releasing sqlite_db_access lock")
      end
      lock_release_resolver()
    end
  end

  local function setup_worker_message_handler (w, on_ready)
    w.onmessage = function (_, ev)
      if ev.data and ev.data.type == "db_error" then
        if verbose then
          print("[proxy] Worker reported db_error:", ev.data.error)
        end
        release_provider()
        if document and document.body then
          document.body.classList:add("db-error")
          document.body:dispatchEvent(js.CustomEvent:new("db-error", {
            detail = { error = ev.data.error }
          }))
        end
      elseif ev.data and ev.data.type == "worker_ready" then
        if verbose then
          print("[proxy] Worker signaled ready")
        end
        if on_ready then
          on_ready()
        end
      end
    end
    w.onerror = function (_, ev)
      if verbose then
        print("[proxy] Worker error:", ev and ev.message)
      end
      release_provider()
      if document and document.body then
        document.body.classList:add("db-error")
        document.body:dispatchEvent(js.CustomEvent:new("db-error", {
          detail = { error = ev and ev.message or "worker crashed" }
        }))
      end
    end
  end

  if verbose then
    print("[proxy] Initializing sqlite proxy")
  end

  local function get_client_id ()
    local nonce = "client_id_" .. tostring(math.random()):sub(3)
    if verbose then
      print("[proxy] Getting client ID with nonce:", nonce)
    end
    local found_client_id = nil
    navigator.locks:request(nonce, function ()
      return async(function ()
        local ok, state = navigator.locks:query():await()
        if verbose then
          print("[proxy] Lock query result - ok:", ok, "state:", state)
        end
        if ok and state and state.held then
          local held = state.held
          if verbose then
            print("[proxy] Held locks count:", held.length)
          end
          for i = 1, held.length do
            local lock = held[i]
            if verbose then
              print("[proxy] Checking lock", i, "name:", lock and lock.name, "clientId:", lock and lock.clientId)
            end
            if lock and lock.name == nonce then
              if verbose then
                print("[proxy] Found our lock, clientId:", lock.clientId)
              end
              found_client_id = lock.clientId
              break
            end
          end
        end
        if verbose and not found_client_id then
          print("[proxy] Failed to find client ID")
        end
        return true
      end)
    end):await()
    return found_client_id
  end

  local function close_provider_connection ()
    if current_provider_port then
      current_provider_port:close()
      current_provider_port = nil
    end
    set_db(nil)
  end

  local function request_provider_port (counter)
    if verbose then
      print("[proxy] request_provider_port called, counter:", counter, "provider_counter:", provider_counter, "is_provider:", is_provider, "db:", db)
    end
    if counter ~= provider_counter then return end
    if is_provider then return end
    if db then return end
    if not navigator.serviceWorker.controller then
      if verbose then
        print("[proxy] No SW controller yet, will retry")
      end
      util.set_timeout(function ()
        request_provider_port(counter)
      end, 500)
      return
    end

    local nonce = "req_" .. tostring(math.random()):sub(3)
    if verbose then
      print("[proxy] Requesting provider port with nonce:", nonce)
    end

    local function on_sw_message (_, ev)
      if verbose then
        print("[proxy] Received SW message:", ev.data and ev.data.type, "nonce:", ev.data and ev.data.nonce, "expected nonce:", nonce)
      end
      if ev.data and ev.data.type == "db_port" and ev.data.nonce == nonce then
        navigator.serviceWorker:removeEventListener("message", on_sw_message)
        local port = ev.ports and ev.ports[1]
        if verbose then
          print("[proxy] Received db_port, port:", port, "counter:", counter, "provider_counter:", provider_counter, "is_provider:", is_provider)
        end
        if port and counter == provider_counter and not is_provider then
          if verbose then
            print("[proxy] Becoming consumer with port")
          end
          current_provider_port = port
          set_db(port)
          if opts.on_worker_connection then opts.on_worker_connection() end
          if ready_resolver then
            ready_resolver()
            ready_resolver = nil
          end
        elseif port then
          if verbose then
            print("[proxy] Closing stale port")
          end
          port:close()
        end
      end
    end
    navigator.serviceWorker:addEventListener("message", on_sw_message)

    if verbose then
      print("[proxy] Broadcasting request to provider")
    end
    broadcast_channel:postMessage(val({
      type = "request",
      nonce = nonce
    }, true))

    util.set_timeout(function ()
      if counter == provider_counter and not db and not is_provider then
        local controller = navigator.serviceWorker.controller
        if controller then
          if verbose then
            print("[proxy] Fetching port from SW with nonce:", nonce)
          end
          controller:postMessage(val({
            type = "get_port",
            nonce = nonce
          }, true))
        end
      end
    end, 100)

    util.set_timeout(function ()
      if counter == provider_counter and not db and not is_provider then
        if verbose then
          print("[proxy] Port request timeout, retrying...")
        end
        navigator.serviceWorker:removeEventListener("message", on_sw_message)
        request_provider_port(counter)
      end
    end, 2000)
  end

  local function create_worker_port ()
    return rpc.create_port(worker)
  end

  broadcast_channel.onmessage = function (_, ev)
    local data = ev.data
    if verbose then
      print("[proxy] Received broadcast:", data and data.type, "clientId:", data and data.clientId)
    end
    if not data then return end

    if data.type == "provider" then
      if verbose then
        print("[proxy] Provider announced, is_provider:", is_provider, "client_id:", client_id)
      end
      if is_provider and data.clientId and data.clientId ~= client_id then
        if verbose then
          print("[proxy] Another tab became provider, releasing our provider role")
        end
        release_provider()
      elseif not is_provider and client_id then
        if verbose then
          print("[proxy] Reconnecting to new provider")
        end
        close_provider_connection()
        provider_counter = provider_counter + 1
        request_provider_port(provider_counter)
      end

    elseif data.type == "request" and is_provider and data.nonce then
      if verbose then
        print("[proxy] Consumer requesting port, nonce:", data.nonce)
      end
      local controller = navigator.serviceWorker.controller
      if not controller then
        if verbose then
          print("[proxy] No SW controller, cannot send port")
        end
        return
      end

      async(function ()
        local _, port = create_worker_port():await()
        if verbose then
          print("[proxy] Storing port in SW for consumer to fetch, nonce:", data.nonce)
        end

        controller:postMessage(
          val({ type = "store_port", nonce = data.nonce }, true),
          { port }
        )
      end)

    end
  end

  return core, util.promise(function (complete)
    ready_resolver = function ()
      complete(true)
    end

    async(function ()
      if verbose then
        print("[proxy] Waiting for SW ready...")
      end
      local ok = navigator.serviceWorker.ready:await()
      if verbose then
        print("[proxy] SW ready callback, ok:", ok)
      end
      if not ok then return end

      local cid = get_client_id()
      if verbose then
        print("[proxy] Got client ID:", cid)
      end
      if not cid then
        if verbose then
          print("[proxy] No client ID, cannot proceed")
        end
        return
      end
      client_id = cid

      if verbose then
        print("[proxy] Acquiring context lock for client:", client_id)
      end
      navigator.locks:request(client_id, function ()
        if verbose then
          print("[proxy] Context lock acquired")
        end
        return hold_lock()
      end):catch(function () end)

      local function try_become_provider ()
        if verbose then
          print("[proxy] try_become_provider called, is_provider:", is_provider, "becoming_provider:", becoming_provider, "hidden:", document.hidden)
        end
        if is_provider or becoming_provider then return end
        if document.hidden then return end
        becoming_provider = true
        if verbose then
          print("[proxy] Requesting sqlite_db_access lock...")
        end
        lock_abort = AbortController:new()
        navigator.locks:request("sqlite_db_access", val({ signal = lock_abort.signal }, true), function ()
          becoming_provider = false
          if verbose then
            print("[proxy] Acquired sqlite_db_access lock - becoming provider!")
          end
          is_provider = true

          if verbose then
            print("[proxy] Initializing database worker...")
          end
          local p, w = init_worker(bundle_path)
          worker = w
          set_db(p)
          if verbose then
            print("[proxy] Database worker initialized, db:", db, "worker:", worker)
          end
          setup_worker_message_handler(worker, function ()
            if verbose then
              print("[proxy] Announcing as provider, clientId:", client_id)
            end
            broadcast_channel:postMessage(val({
              type = "provider",
              clientId = client_id
            }, true))

            if opts.on_worker_connection then opts.on_worker_connection() end

            if ready_resolver then
              if verbose then
                print("[proxy] Resolving ready promise")
              end
              ready_resolver()
              ready_resolver = nil
            end
          end)

          return hold_lock()
        end):catch(function (_, e)
          becoming_provider = false
          if e and e.name == "AbortError" then
            if verbose then
              print("[proxy] Lock request aborted (tab backgrounded)")
            end
          else
            if verbose then
              print("[proxy] Lock request failed:", e)
            end
          end
        end)
      end

      try_become_provider()

      document:addEventListener("visibilitychange", function ()
        if document.hidden then
          release_provider()
        else
          if verbose then
            print("[proxy] Tab visible, trying to become provider or consumer")
          end
          try_become_provider()
          if not is_provider and not becoming_provider then
            provider_counter = provider_counter + 1
            request_provider_port(provider_counter)
          end
        end
      end)

      js.window:addEventListener("pagehide", function ()
        release_provider()
      end)

      if verbose then
        print("[proxy] Also trying to connect as consumer...")
      end
      request_provider_port(provider_counter)
    end)
  end)
end
