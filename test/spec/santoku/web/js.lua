

local assert = require("luassert")
local test = require("santoku.test")
local js = require("santoku.web.js")

test("js", function ()

  test("global", function ()

    local console = js.console
    local log = console.log

    assert.equals(type(log), "function")

  end)

end)













