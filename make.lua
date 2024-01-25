local compat = require("santoku.compat")

local env = {

  name = "santoku-web",
  version = "0.0.86-1",
  variable_prefix = "TK_WEB",
  license = "MIT",
  public = true,

  dependencies = {
    "lua >= 5.1",
    "santoku >= 0.0.162-1",
    "lsqlite3 >= 0.9.5-1"
  },




  cxxflags = "--std=c++17",
  ldflags = "--bind",

  test = {
    ldflags = "--bind",
    dependencies = {
      "santoku-test >= 0.0.8-1",
      "luassert >= 1.9.0-1",
      "luacov >= scm-1",
    }
  },

}

env.homepage = "https://github.com/treadwelllane/lua-" .. env.name
env.tarball = env.name .. "-" .. env.version .. ".tar.gz"
env.download = env.homepage .. "/releases/download/" .. env.version .. "/" .. env.tarball

return {
  type = "lib",
  env = env,
}

