rockspec_format = "3.0"
package = "tab"
version = "scm-1"
source = {
  url = "git+https://github.com/timm/tab"
}
description = {
  summary = "A good guess from a few dozen labels.",
  detailed = [[
    Range means, shrunk to the grand mean, weighed by variance.
    Incremental tabular learning: Naive Bayes, range-means
    regression/optimization, effect-size + significance tests.
    One file, no dependencies, Lua 5.1+ and LuaJIT.

    LuaJIT is the fast one and what the scripts call; on a few dozen
    labels it is the difference between milliseconds and seconds.
    Any Lua 5.1 to 5.5 runs it correctly.  LuaRocks picks the
    interpreter from its own configuration, not from this file, so
    to install against LuaJIT use a LuaJIT-configured luarocks
    (luarocks --lua-version=5.1 install tab).]],
  homepage = "https://github.com/timm/tab",
  license = "MIT",
  labels = {"machine-learning", "data", "csv"}
}
dependencies = {
  "lua >= 5.1"
}
build = {
  type = "builtin",
  modules = {
    tab = "tab.lua",
    ["tab-eg"] = "tab-eg.lua"
  },
  install = {
    bin = { tab = "bin/tab" }
  }
}
