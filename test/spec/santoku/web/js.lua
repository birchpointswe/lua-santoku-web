local test = require("santoku.test")
local err = require("santoku.error")
local validate = require("santoku.validate")
local val = require("santoku.web.val")
local js = require("santoku.web.js")

local assert = err.assert
local eq = validate.isequal

collectgarbage("stop")

test("equality", function ()
  local c0 = js.console
  local c1 = js.console
  assert(eq(c0:val(), c1:val()))
end)

val.global("setTimeout"):call(nil, function ()

  collectgarbage("collect")
  val.global("gc"):call(nil)
  collectgarbage("collect")
  val.global("gc"):call(nil)
  collectgarbage("collect")

  val.global("setTimeout"):call(nil, function ()


    assert(val.IDX_REF_TBL.n == 2, "IDX_REF_TBL.n ~= 2")







    if os.getenv("TK_WEB_PROFILE") == "1" then
      require("santoku.profile")()
    end

  end)

end, 500)
