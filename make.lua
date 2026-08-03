local env = {

  name = "santoku-web",
  version = "1.0.1-1",
  variable_prefix = "TK_WEB",
  license = "MIT",
  public = true,

  cflags = {},

  dependencies = {
    "lua == 5.1",
    "santoku >= 1.0.0, < 2.0.0",
    "santoku-mustache >= 1.0.0, < 2.0.0",
    "santoku-http >= 1.0.0, < 2.0.0",
    "santoku-lpeg >= 1.0.0, < 2.0.0",
    "lua-cjson == 2.1.0.10-1"
  },

  build = {
    wasm = {
      ldflags = {
        "-sWASM_BIGINT", "-sDEFAULT_LIBRARY_FUNCS_TO_INCLUDE='$stringToNewUTF8'",
        "-sEXPORTED_FUNCTIONS=_malloc,_free", "-sEXPORTED_RUNTIME_METHODS=stringToUTF8,lengthBytesUTF8,UTF8ToString,stringToNewUTF8,HEAPU8",
      },
    },
  },

  test = {
    wasm = {
      ldflags = {
        "-Og", "-sWASM_BIGINT", "-sDEFAULT_LIBRARY_FUNCS_TO_INCLUDE='$stringToNewUTF8'",
        "-sEXPORTED_FUNCTIONS=_malloc,_free", "-sEXPORTED_RUNTIME_METHODS=stringToUTF8,lengthBytesUTF8,UTF8ToString,stringToNewUTF8,HEAPU8",
      },
    },
  },

}

env.homepage = "https://github.com/birchpointswe/lua-" .. env.name
env.tarball = env.name .. "-" .. env.version .. ".tar.gz"
env.download = env.homepage .. "/releases/download/" .. env.version .. "/" .. env.tarball

return { env = env }
