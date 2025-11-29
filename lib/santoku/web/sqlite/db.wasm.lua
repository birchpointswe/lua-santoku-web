










local sqlite = require("santoku.web.sqlite")
local migrate = require("santoku.sqlite.migrate")

local M = {}





M.define = function (db_name, migrations, accessor_builder)
  local mod = {}
  local db_instance = nil
  local accessors = nil


  mod.init = function (callback)
    if db_instance then
      callback(true, mod)
      return
    end

    sqlite.open_opfs("/" .. db_name, function (ok, db)
      if not ok then
        return callback(false, db)
      end


      migrate(db, migrations)

      db_instance = db


      accessors = accessor_builder(db)


      for k, v in pairs(accessors) do
        mod[k] = v
      end


      mod.handlers = {}
      for k, v in pairs(accessors) do
        if type(v) == "function" then
          mod.handlers[k] = v
        end
      end

      callback(true, mod)
    end)
  end


  mod.raw = function ()
    return db_instance
  end

  return mod
end

return M
