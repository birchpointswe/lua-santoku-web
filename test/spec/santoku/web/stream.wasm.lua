local test = require("santoku.test")
local err = require("santoku.error")
local validate = require("santoku.validate")
local js = require("santoku.web.js")
local async = require("santoku.web.async")
local stream = require("santoku.web.stream")

local assert = err.assert
local eq = validate.isequal

local Promise = js.Promise

local net = stream.builtin("net")

if not net then

  test("node net unavailable, driver degrades", function ()
    local res
    stream.connect({ host = "h", port = 1, tls = false,
      data = function () end,
    }, function (ok, e)
      res = { ok = ok, e = e }
    end)
    assert(eq(false, res.ok))
    assert(eq("node socket module unavailable", res.e))
  end)

else

  test("loopback echo roundtrip", function ()
    async(function ()
      local p = Promise:new(function (this, resolve)
        local server = net:createServer(function (_, s)
          s:on("data", function (_, b)
            s:write(b)
          end)
        end)
        server:listen(0, "127.0.0.1", function ()
          local port = server:address().port
          local got = ""
          local conn
          stream.connect({
            host = "127.0.0.1", port = port, tls = false,
            data = function (chunk)
              got = got .. chunk
              if #got >= 4 then
                conn.close()
                server:close()
                resolve(this, got)
              end
            end,
          }, function (ok, c)
            assert(ok, "connect failed")
            conn = c
            conn.write("ab")
            conn.write("cd")
          end)
        end)
      end)
      local ok, result = p:await()
      assert(eq(true, ok))
      assert(eq("abcd", result))
    end)
  end)

  test("closed callback fires on server close", function ()
    async(function ()
      local p = Promise:new(function (this, resolve)
        local server = net:createServer(function (_, s)
          s:on("data", function ()
            s:destroy()
          end)
        end)
        server:listen(0, "127.0.0.1", function ()
          local port = server:address().port
          stream.connect({
            host = "127.0.0.1", port = port, tls = false,
            data = function () end,
            closed = function ()
              server:close()
              resolve(this, "closed")
            end,
          }, function (ok, c)
            assert(ok, "connect failed")
            c.write("x")
          end)
        end)
      end)
      local ok, result = p:await()
      assert(eq(true, ok))
      assert(eq("closed", result))
    end)
  end)

  test("connection refused settles false", function ()
    async(function ()
      local p = Promise:new(function (this, resolve)
        local server = net:createServer(function () end)
        server:listen(0, "127.0.0.1", function ()
          local port = server:address().port
          server:close(function ()
            stream.connect({
              host = "127.0.0.1", port = port, tls = false,
              data = function () end,
              closed = function ()
                resolve(this, "wrong: closed fired")
              end,
            }, function (ok)
              if not ok then
                resolve(this, "refused")
              end
            end)
          end)
        end)
      end)
      local ok, result = p:await()
      assert(eq(true, ok))
      assert(eq("refused", result))
    end)
  end)

end
