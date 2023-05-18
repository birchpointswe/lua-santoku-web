

local assert = require("luassert")
local test = require("santoku.test")
local val = require("santoku.web.val")

test("val", function ()

  test("global", function ()

    test("returns a global object", function ()
      local v = val.global("console")
      assert.equals("object", v:typeof():str())
    end)

  end)

  test("object", function ()

    test("creates a js object", function ()
      local o = val.object()
      assert.equals("object", o:typeof():str())
      assert.equals("Object", o:get(val("constructor")):get(val("name")):str())
    end)

  end)

  test("array", function ()



    test("creates a js array", function ()
      local a = val.array()
      assert.equals("object", a:typeof():str())
      assert.equals("Array", a:get(val("constructor")):get(val("name")):str())
    end)

  end)

  test("undefined", function ()

    test("creates an undefined value", function ()
      local a = val.undefined()
      assert.equals("undefined", a:typeof():str())
    end)

  end)

  test("null", function ()

    test("creates a null value", function ()
      local a = val.null()
      assert.equals("object", a:typeof():str())
    end)

  end)

  test("from string", function ()

    test("creates a string value", function ()
      local a = val("hello")
      assert.equals("string", a:typeof():str())
      assert.equals("hello", a:str())
    end)

  end)

  test("from number", function ()



    test("creates a number value", function ()
      local a = val(100.6)
      assert.equals("number", a:typeof():str())

    end)

  end)

  test("from boolean", function ()


    test("creates a boolean value", function ()
      local a = val(true)


      local a = val(false)


    end)

  end)

  test("from table", function ()

    test("creates an object proxy", function ()
      local source = { a = 1, b = "2" }
      local a = val(source)
      assert.equals("object", a:typeof():str())
      assert.equals("Object", a:get(val("constructor")):get(val("name")):str())
      assert.equals(source, a:tbl())
      assert.same({ a = 1, b = "2" }, a:tbl())
      a:set(val("c"), val(3))
      assert.equals(source, a:tbl())
      assert.same({ a = 1, b = "2", c = 3 }, a:tbl())
    end)

    test("creates an object proxy with object constructor", function ()
      local source = { a = 1, b = "2" }
      local a = val(source, val.global("Object"))
      assert.equals("object", a:typeof():str())
      assert.equals("Object", a:get(val("constructor")):get(val("name")):str())
      assert.equals(source, a:tbl())
      assert.same({ a = 1, b = "2" }, a:tbl())
      a:set(val("c"), val(3))
      assert.equals(source, a:tbl())
      assert.same({ a = 1, b = "2", c = 3 }, a:tbl())
    end)

    test("creates an array proxy", function ()
      local source = { 1, 2, 3, 4 }
      local a = val(source, val.global("Array"))
      assert.equals("object", a:typeof():str())
      assert.equals("Array", a:get(val("constructor")):get(val("name")):str())
      assert.equals(source, a:tbl())
      assert.same({ 1, 2, 3, 4 }, a:tbl())
    end)

  end)

  test("from function", function ()
    local fn = function (a) return a + 4 end
    local a = val(fn)
    assert.equals("function", a:typeof():str())
    assert.equals(fn, a:fn())
    local x = a:fn()(2)
    assert.equals(6, x)
  end)

  test("object", function ()

    test("set/get", function ()
      local obj = val.object()
      obj:set(val("a"), val(1))
      local one = obj:get(val("a"))
      assert.equals("number", one:typeof():str())
      assert.equals(1, one:num())
    end)

  end)

  test("call", function ()

    test("JSON.stringify({})", function ()
      local obj = val.object()
      local JSON = val.global("JSON")
      local r = JSON:call("stringify", obj)
      assert.equals("string", r:typeof():str())
      assert.equals("{}", r:str())
    end)

    test("JSON.stringify({ a: 1, b: 2 })", function ()
      local obj = val.object()
      obj:set(val("a"), val(1))
      obj:set(val("b"), val(2))
      local JSON = val.global("JSON")
      local r = JSON:call("stringify", obj)
      assert.equals("string", r:typeof():str())
      assert.equals("{\"a\":1,\"b\":2}", r:str())
    end)

    test("Math.max(1, 3, 2)", function ()
      local Math = val.global("Math")
      local r = Math:call("max", val(1), val(3), val(2))
      assert.equals("number", r:typeof():str())
      assert.equals(3, r:num())
    end)

  end)

  test("new", function ()

    test("new Map()", function ()
      local Map = val.global("Map")
      local m = Map:new()
      assert.equals("object", m:typeof():str())
      assert.equals("Map", m:get(val("constructor")):get(val("name")):str())
      m:call("set", val(1), val(2))
      local r = m:call("get", val(1))
      assert.equals("number", r:typeof():str())
      assert.equals(2, r:num())
    end)

    test("new Map([[1, 2], [3, 4]])", function ()
      local arr = val.array()
      local ent1 = val.array()
      ent1:call("push", val(1))
      ent1:call("push", val(2))
      arr:call("push", ent1)
      local ent2 = val.array()
      ent2:call("push", val(3))
      ent2:call("push", val(4))
      arr:call("push", ent2)
      local Map = val.global("Map")
      local m = Map:new(arr)
      assert.equals("object", m:typeof():str())
      assert.equals("Map", m:get(val("constructor")):get(val("name")):str())
      local r = m:call("get", val(1))
      assert.equals("number", r:typeof():str())
      assert.equals(2, r:num())
      local r = m:call("get", val(3))
      assert.equals("number", r:typeof():str())
      assert.equals(4, r:num())
    end)

  end)

  test("integration", function ()

    test("set & call function", function ()
      local obj = val.object()
      obj:set(val("square"), val(function (a)
        return a * a
      end))
      local ret = obj:call("square", val(20))
      assert.equals("number", ret:typeof():str())
      assert.equals(400, ret:num())
    end)

  end)

end)































