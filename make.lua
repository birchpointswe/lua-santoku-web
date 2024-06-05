local env = {

  name = "santoku-web",
  version = "0.0.106-1",
  variable_prefix = "TK_WEB",
  license = "MIT",
  public = true,

  dependencies = {
    "lua >= 5.1",
    "santoku >= 0.0.204-1",
    "santoku-sqlite >= 0.0.13-1",
    "santoku-fs >= 0.0.31-1",
  },




  cxxflags = { "--std=c++17" },
  ldflags = { "--bind"  },

  test = {
    cflags = { "-sDEFAULT_LIBRARY_FUNCS_TO_INCLUDE='$stringToNewUTF8'" },
    ldflags = { "--bind" },
    dependencies = {

      "luacov >= 0.15.0-1",
    },

  },


}

env.homepage = "https://github.com/treadwelllane/lua-" .. env.name
env.tarball = env.name .. "-" .. env.version .. ".tar.gz"
env.download = env.homepage .. "/releases/download/" .. env.version .. "/" .. env.tarball

return {
  type = "lib",
  env = env,
}

