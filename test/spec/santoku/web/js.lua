local assert = require("luassert")
local test = require("santoku.test")
local compat = require("santoku.compat")
local gen = require("santoku.gen")
local vec = require("santoku.vector")
local val = require("santoku.web.val")
local js = require("santoku.web.js")

collectgarbage("stop")

test("js", function ()





  test("unpack a javascript array", function ()
    local arr = val({ 1, 2, 3 }, true)
    arr = arr:lua()
    local a, b, c = compat.unpack(arr)
    assert.same({ 1, 2, 3 }, { a, b, c })
  end)

  test("pairs over a javascript object", function ()
    local obj = val({ a = 1 }, true):lua()
    assert.same({{"a", 1, n = 2}, n = 1}, gen.pairs(obj):vec())
  end)

  test("Object.keys() on wrapped val", function ()
    local obj = val({ a = 1, b = 2 })
    local keys = js.Object:keys(obj)
    local vkeys = vec(compat.unpack(keys)):sort()
    assert.same({ "a", "b", n = 2 }, vkeys)
  end)

  test("Object.values() on wrapped val", function ()
    local obj = val({ a = 1, b = 2 })
    local values = js.Object:values(obj)
    local vvalues = vec(compat.unpack(values)):sort()
    assert.same({ 1, 2, n = 2 }, vvalues)
  end)











  test("equality", function ()
    local c0 = js.console
    local c1 = js.console
    assert.equals(c0:val(), c1:val())
  end)

end)

collectgarbage("collect")
val.global("gc"):call(nil)

val.global("setTimeout", function ()

  local cntt = 0
  for k, v in pairs(val.IDX_REF_TBL) do

    cntt = cntt + 1
  end



  assert.equals(0, cntt, "IDX_REF_TBL not clean")

end, 5000)
