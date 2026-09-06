local err = require("santoku.error")
local validate = require("santoku.validate")
local test = require("santoku.test")
local val = require("santoku.web.val")
local env = require("santoku.env")

local assert = err.assert
local eq = validate.isequal

collectgarbage("stop")

test("global", function ()
  local vDate = val.global("Date")
  local _ = vDate:lua()
end)

test("val string to uint8array", function ()
  local _ = val.bytes("ABC")
end)

test("object set/get", function ()
  local obj = val.global("Object"):call(nil)
  obj:set("a", 1)
  local one = obj:get("a")
  assert(eq("number", one:typeof():lua()))
  assert(eq(1, one:lua()))
end)

test("array keys", function ()
  local vObject = val.global("Object")
  local Object = vObject:lua()
  local _ = Object.keys
end)

test("basic val", function ()
  local _ = val({ 1, 2, 3, 4, 5 })
end)

val.global("setTimeout"):call(nil, function ()

  collectgarbage("collect")
  val.global("gc"):call(nil)
  collectgarbage("collect")
  val.global("gc"):call(nil)
  collectgarbage("collect")

  val.global("setTimeout"):call(nil, function ()

    assert(val.IDX_REF_TBL.n == 2, "IDX_REF_TBL.n ~= 2")

    if env.var("TK_WEB_PROFILE", nil) == "1" then
      require("santoku.profile")()
    end

  end)

end, 500)
