local assert = require("luassert")
local test = require("santoku.test")
local compat = require("santoku.compat")
local val = require("santoku.web.val")








































test("js", function ()

  test("val(x) wraps a lua table with a proxy", function ()
    local t = { 1, { 2, 3 }, 4 }
    local v = val(t)
    assert.equals(false, v:isval())
    assert.equals(true, v:islua())
  end)

  test("val(x, true) converts a lua numeric table to an array", function ()
    local t = { 1, { 2, 3 }, 4 }
    local v = val(t, true)
    assert.equals(true, v:isval())
    assert.equals(false, v:islua())
  end)

  test("val(x, true) converts a lua map table to an object", function ()
    local t = { a = 1, b = { c = 3 } }
    local v = val(t, true)
    assert.equals(true, v:isval())
    assert.equals(false, v:islua())
  end)

  test("x:val() returns the val as is", function ()
    local t = { 1, { 2, 3 }, 4 }
    local v = val(t):val()
    assert.equals(false, v:isval())
    assert.equals(true, v:islua())
  end)

  test("x:val(true) returns the val converted to a val", function ()
    local t = { 1, { 2, 3 }, 4 }
    local v = val(t):val(true)
    assert.equals(true, v:isval())
    assert.equals(false, v:islua())
  end)

  test("x:val(true) returns the val converted to a val", function ()
    local t = { a = 1, b = { c = 2 } }
    local v = val(t):val(true)
    assert.equals(true, v:isval())
    assert.equals(false, v:islua())
  end)









  test("unpack a javascript array", function ()
    local arr = val({ 1, 2, 3 }, true):lua()
    local a, b, c = compat.unpack(arr)
    assert.same({ 1, 2, 3 }, { a, b, c })
  end)

end)
