











local shared = require("santoku.web.sqlite.shared")

local M = {}

M.init = function (opts)
  opts = opts or {}

  local name = opts.name or "app"
  local db_module = opts.db
  local main_fn = opts.main

  local service_name = name .. "-db"

  if db_module then

    db_module.init(function (ok, db)
      if not ok then
        print("Failed to initialize database:", db)
        return
      end


      local service = shared.SharedService(service_name, function ()
        return shared.create_provider_port(db.handlers, false)
      end)


      service.activate()


      if main_fn then
        main_fn(db)
      end
    end)
  else

    if main_fn then
      main_fn()
    end
  end
end

return M
