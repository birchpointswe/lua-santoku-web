local assert = require("luassert")
local test = require("santoku.test")



local val = require("santoku.web.val")
local js = require("santoku.web.js")

collectgarbage("stop")

test("js", function ()









































  test("equality", function ()
    local c0 = js.console
    local c1 = js.console
    assert.equals(c0:val(), c1:val())
  end)

end)

val.global("setTimeout"):call(nil, function ()

  collectgarbage("collect")
  val.global("gc"):call(nil)
  collectgarbage("collect")
  val.global("gc"):call(nil)
  collectgarbage("collect")

  val.global("setTimeout"):call(nil, function ()


    assert.equals(2, val.IDX_REF_TBL_N)

    if os.getenv("TK_WEB_PROFILE") == "1" then
      require("santoku.profile")()
    end

  end)

end, 500)
