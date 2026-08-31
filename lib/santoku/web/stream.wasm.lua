local js = require("santoku.web.js")
local val = require("santoku.web.val")

local function builtin (name)
  local okp, p = pcall(function ()
    return js.process
  end)
  if not okp or not p then
    return nil
  end
  if p.getBuiltinModule then
    local okm, m = pcall(function ()
      return p:getBuiltinModule(name)
    end)
    if okm and m then
      return m
    end
  end
  if p.mainModule and p.mainModule.require then
    local okm, m = pcall(function ()
      return p.mainModule:require(name)
    end)
    if okm and m then
      return m
    end
  end
  return nil
end

local M = {}

M.builtin = builtin

M.connect = function (opts, done)
  local mod = builtin(opts.tls == false and "net" or "tls")
  if not mod then
    return done(false, "node socket module unavailable")
  end
  local settled = false
  local established = false
  local lasterr = nil
  local function settle (ok, res)
    if settled then return end
    settled = true
    established = ok and true or false
    done(ok, res)
  end
  local sock
  local conn = {
    write = function (d)
      sock:write(d, "latin1")
      return true
    end,
    close = function ()
      sock:destroy()
    end,
  }
  local o = { host = opts.host, port = opts.port }
  if opts.tls ~= false then
    o.servername = opts.sslname or opts.host
    if opts.verify == false then
      o.rejectUnauthorized = false
    end
  end
  local function onconnect ()
    settle(true, conn)
  end
  if opts.tls == false then
    sock = mod:createConnection(val(o, true), onconnect)
  else
    sock = mod:connect(val(o, true), onconnect)
  end
  sock:on("data", function (_, buf)
    opts.data(buf:toString("latin1"))
  end)
  sock:on("error", function (_, e)
    local msg = tostring((e and e.message) or e or "error")
    if settled then
      lasterr = msg
    else
      settle(false, msg)
    end
  end)
  sock:on("close", function ()
    if not settled then
      settle(false, lasterr or "closed")
    elseif established and opts.closed then
      opts.closed(lasterr)
    end
  end)
  return conn
end

return M
