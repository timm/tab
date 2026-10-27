# tab

A good guess from a few dozen labels. Range means, shrunk to the
grand mean, weighed by variance. Lua, no dependencies, one file.

    tab.lua       the learner
    tab-eg.lua    the rigs
    tab/          the common scripts: sh (work shell), run (parallel
                  experiments), push (save upstream)
    etc/          support code and config (lgbm.py, nn.py, charts.py ...)
    docs/         the figures

Try:

    luajit tab.lua --all        # unit tests
    luajit tab.lua --secs       # time a train+guess
    tab/run results             # every learner, every data set

Or `luarocks make tab-scm-1.rockspec` and then `require "tab"`.

Data: [moot](https://github.com/timm/moot), expected at `~/gits/moot`
(override with `MOOT=...`).

The repo's pre-history lives on branch `26oct25`.

(c) 2026 Tim Menzies, MIT license.
