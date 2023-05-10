

local assert = require("luassert")
local test = require("santoku.test")
local val = require("santoku.web.val")

test("val", function ()

  test("global", function ()

    test("returns", function ()
      local v = val.global("console")
      assert.equals(v:typeof():str(), "object")
    end)

  end)

end)































