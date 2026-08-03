#include "lua.h"
#include "emscripten.h"

int luaopen_santoku_web_dom_install (lua_State *);

EM_JS(void, tk_dom_install, (void), {
<% return readfile("res/web/dom.js") %>
});

int luaopen_santoku_web_dom_install (lua_State *L)
{
  tk_dom_install();
  lua_newtable(L);
  return 1;
}
