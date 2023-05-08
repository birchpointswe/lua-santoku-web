

local assert = require("luassert")
local test = require("santoku.test")
local val = require("santoku.web.val")

test("val", function ()

  test("global", function ()
    test("should return a javascript global", function ()
      local v = val.global("console")
      assert.equals(v:typeof():str(), "object")
    end)
  end)

end)































