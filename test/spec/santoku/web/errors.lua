local js = require("santoku.web.js")
local test = require("santoku.test")
local assert = require("luassert")

local global = js.global
local process = js.process
local Promise = js.Promise





test("errors", function ()

  test("promise", function ()
    Promise:new(function (_, res, rej)
      error("test")
    end):await(function (_, ok, err)
      assert.equals(false, ok)
      assert.equals("test", err)
    end)
  end)















end)
