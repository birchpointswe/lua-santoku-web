





local vec = require("santoku.vector")

return function (callback, global)

  local JSON = global.JSON
  local console = global.console



  local oldwinerr = global and global.onerror
  local oldfetch = global and global.fetch
  local logtypes = vec("log", "error")
  local oldlogs = {}
  local oldprint = nil

  local function wrapPrint ()
    oldprint = print
    _G.print = function (...)
      oldprint(...)
      callback(JSON:stringify({
        source = "print",
        args = { ... }
      }))
    end
  end

  local function wrapLog (typ)
    if oldlogs[typ] then
      return
    end
    oldlogs[typ] = console[typ]
    console[typ] = function (_, ...)
      oldlogs.log(console, ...)
      callback(JSON:stringify({
        source = "console",
        typ, args = { ... }
      }))
    end
  end

  local function wrapLogs ()
    logtypes:each(function(lt)
      wrapLog(lt)
    end)
  end

  local function onErr (ev)
    callback(JSON:stringify({
      source = "error",
      event = ev,
      name = ev and ev.name,
      message = ev and ev.message,
    }))
    if oldwinerr then
      oldwinerr(console, ev)
    end
  end

  local function wrapErr ()
    if global then
      global:addEventListener("error", function (_, ev)
        onErr(ev)
      end)
    end
  end


















































  wrapPrint()
  wrapErr()
  wrapLogs()


  return {
    oldlogs = oldlogs,
    oldwinerr = oldwinerr,
    oldfetch = oldfetch,
    onErr = onErr
  }

end
