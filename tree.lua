#!/usr/bin/env lua
-- tree.lua: the tree now lives inside tab.lua.  This shim keeps the
-- old name working, for requires and for the command line.
package.path = (arg and arg[0] and arg[0]:match"^(.*)/" or ".")
               .. "/?.lua;" .. package.path
local tab = require "tab"
if (arg and arg[0] or ""):find"tree%.lua$" then
  tab.the = tab.cli()
  ;(tab.slow[tab.the.go] or tab.slow.all)() end
return tab
