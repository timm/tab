# tab

<p align="center"><img src="docs/logo.png"  ></p>

[lua 101](docs/lua101.md) ·
[lua, more](docs/luamore.md) ·
[learn x in y](lua/learnxiny.md) ·
[tab.lua](docs/tab.md) ·
[tab-eg.lua](docs/tab-eg.md) ·
[license](https://github.com/timm/tab/blob/main/LICENSE.md)

A good guess from a few dozen labels. Range means, shrunk to the
grand mean, weighed by variance. Lua, no dependencies, one file.

    tab.lua       the learner
    tab-eg.lua    the rigs
    ,/            the common scripts: sh (work shell), run (parallel
                  experiments), md (lua to markdown), pdf,
                  push (save upstream)
    bin/          the installed command (see the rockspec)
    etc/          support code and config (lgbm.py, nn.py, charts.py ...)
    lua/          learn x in y minutes, in tab.lua
    docs/         the figures, the tutorials, the literate source

## Install

Any Lua 5.1+ runs tab.lua; [LuaJIT](https://luajit.org) is the
fast one and what the scripts call. No other dependencies.

    brew install luajit          # macOS
    sudo apt install luajit      # debian, ubuntu

(Plain `lua` works too: `brew install lua` / `apt install lua5.4`,
then swap `lua` for `luajit` below.)

The data is [moot](https://github.com/timm/moot) -- a few hundred
csv files for classify, regress, optimize. The code expects it at
`~/gits/moot` (override with `MOOT=...`):

    mkdir -p ~/gits; cd ~/gits
    git clone --depth 1 https://github.com/timm/moot

To use tab as a library elsewhere, install it as a rock:

    luarocks make tab-scm-1.rockspec   # then: require "tab"

## Try

    luajit tab.lua               # print the help
    luajit tab.lua --all         # unit tests (needs moot)
    luajit tab.lua --secs        # time a train+guess
    luajit tab.lua file=x.csv --secs   # ... on your own csv
    ,/run results                # every learner, every data set

The repo's pre-history lives on branch `26oct25`.

(c) 2026 Tim Menzies, [MIT license](LICENSE.md).
