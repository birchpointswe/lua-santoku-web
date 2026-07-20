#include "lua.h"
#include "emscripten.h"

int luaopen_santoku_web_asyncsched (lua_State *);

EM_JS(void, tk_asyncsched_install, (void), {
  var scheduled = false;
  function drain() {
    scheduled = false;
    if (globalThis.__luaAsyncDrain) globalThis.__luaAsyncDrain();
  }
  globalThis.__luaAsyncSchedule = function() {
    if (!scheduled) {
      scheduled = true;
      setTimeout(drain, 0);
    }
  };
});

int luaopen_santoku_web_asyncsched (lua_State *L)
{
  tk_asyncsched_install();
  lua_newtable(L);
  return 1;
}
