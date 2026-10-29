#!/usr/bin/env lua
-- vim: set ts=2 sw=2 sts=2 et cc=75 :
-- tree.lua: a binary regression tree grown from tab's bins.  Each
-- node carries a payload: the best row that ever reached it.  So one
-- descent answers two questions -- what score to expect here (the
-- node's mean) and which row to actually label (its payload).  A
-- search over rows wants the second answer, and a mean cannot give
-- it, because no row need sit at the mean.
-- usage: luajit tree.lua [name=value | action | file.csv ...]
package.path = (arg[0]:match"^(.*)/" or ".") .. "/?.lua;" .. package.path
local tab = require "tab"
if setfenv then setfenv(1, tab) end          -- tab's _ENV is ours too
local _ENV = tab

NODE = {}

usage = [[
flags:
  depth=4          how deep the tree may grow
  leaf=8           rows each side of a cut needs
  go=all           which action to run
]]
for k, v in usage:gmatch"\n%s+(%a+)=(%S+)" do the[k] = thing(v) end

-- ---- misc ------------------------------------------------------------
-- Return the mean absolute error of `fn` against `y` over `rows`.
function mae(rows,y,fn,    err) --> num
  err = function(row) return abs(y(row) - fn(row)) end
  return nums(rows, err).mu end

-- ---- cuts ------------------------------------------------------------
-- Return where to cut `col`: a NUM at the bin holding its mean, a
-- SYM at its most common value.  One cut point, not a scan of all
-- of them, because the column was already chosen on its bins.
function at(col,    fn) --> atom
  if getmetatable(col) == NUM then return col:bin(col.mu) end
  fn = function(n) return n end
  return (best(col.has, fn)) end

-- Return true when `row` belongs on `cut`'s left: at or below the
-- bin for a NUM, equal to the value for a SYM.  An unknown goes
-- left, where the first cut put the rows we knew most about.
function left(cut,row,    v) --> bool
  v = cut.col:bin(row[cut.col.at])
  if v == "?" then return true end
  if getmetatable(cut.col) == SYM then return v == cut.bin end
  return v <= cut.bin end

-- Return `cut` as text, read going left (`how`=1) or right.
function says(cut,how,    op) --> str
  op = getmetatable(cut.col) == SYM and {"==", "~="} or {"<=", ">"}
  return cut.col.txt .. " " .. op[how] .. " " .. str(cut.bin) end

-- ---- growing ---------------------------------------------------------
-- Return a tree over `rows` of `tbl:TAB`, scored on `y`.  The
-- defaults live here, so `grow` only has to grow.
function Tree(tbl,rows,y) --> NODE
  rows = rows or tbl.rows
  y    = y or function(row) return tbl:ydist(row) end
  return Node(tbl, rows, y, 1):grow() end

-- Return one node over `rows`.  One pass and one `<` gets both the
-- spread and the payload: the best row seen is just the best so far,
-- then one more row, then maybe a replacement.
function Node(tbl,rows,y,lvl,    i,v) --> NODE
  i = new(NODE, {tbl = tbl, rows = rows, y = y, lvl = lvl, n = #rows,
                 sub = tbl:clone(rows), all = Num(), ys = {}})
  for _, row in order(rows) do
    v = y(row); i.ys[row] = v; i.all:add(v)
    if not i.row or v < i.lo then i.row, i.lo = row, v end end
  i.mu = i.all.mu
  return i end

-- Return where to cut `i.rows`: the column whose bins cut the most
-- variance off `i.all`, at that column's own cut point.  This is the
-- same test `rmeans` weighs its columns by.
function NODE.cut(i,    y,fn,k,col) --> dict
  y   = function(row) return i.ys[row] end     -- y, already paid for
  fn  = function(col) return Bins(col, i.rows, y, i.all).w end
  k   = best(i.sub.x, fn)
  col = k and i.sub.x[k]
  return col and {col = col, bin = at(col)} end

-- Return `i`, grown: a cut and two grown kids, or just itself.
function NODE.grow(i,    cut,a,b,t) --> NODE
  if i.n < 2 * the.leaf or i.lvl >= the.depth then return i end
  cut = i:cut()
  if not cut then return i end
  a, b = {}, {}
  for _, row in order(i.rows) do
    t = left(cut, row) and a or b
    t[#t + 1] = row end
  if #a < the.leaf or #b < the.leaf then return i end  -- a bad cut
  i.at    = cut
  i.left  = Node(i.tbl, a, i.y, i.lvl + 1):grow()
  i.right = Node(i.tbl, b, i.y, i.lvl + 1):grow()
  return i end

-- ---- asking ----------------------------------------------------------
-- Return the leaf of `i` that `row` falls into.
function NODE.leaf(i,row) --> NODE
  if not i.at then return i end
  return (left(i.at, row) and i.left or i.right):leaf(row) end

-- Return `row`'s guess: the mean of the leaf it falls into.
function NODE.guess(i,row) --> num
  return i:leaf(row).mu end

-- Return the best row seen where `row` lands: the leaf's payload.
function NODE.pick(i,row) --> row
  return i:leaf(row).row end

-- Return how deep `i` actually grew.
function NODE.depth(i) --> int
  return i.at and max(i.left:depth(), i.right:depth()) or i.lvl end

-- Print `i`, one indented line per node: rows, mean, and the `y` of
-- its payload.
function NODE.show(i,s,    pad) --> nil
  pad = ("|  "):rep(i.lvl - 1)
  print(("%-32s n=%-5d mu=%-6s lo=%s"):format(
          pad .. (s or "root"), i.n, str(i.mu), str(i.lo)))
  if i.at then
    i.left:show(says(i.at, 1))
    i.right:show(says(i.at, 2)) end end

-- ---- start up --------------------------------------------------------
-- Return `the.file` as train and test TABs, and the `y` to score
-- them by.  `y` comes off the train table alone: its column means
-- and sds are all a learner is allowed to have seen.
function halves(    tbl,tr,te) --> TAB
  tbl    = Tab(the.file)
  tr, te = tbl:split()
  tr, te = tbl:clone(tr), tbl:clone(te)
  return tr, te, function(row) return tr:ydist(row) end end

function eg.tree(    tr,te,y) --> nil
  tr, te, y = halves()
  Tree(tr, tr.rows, y):show() end

function eg.all(    tr,te,y,i,lo,m1,m2) --> nil
  tr, te, y = halves()
  i  = Tree(tr, tr.rows, y)
  assert(i.n == #tr.rows, "root holds every training row")
  lo = i.lo
  for _, row in order(tr.rows) do          -- the payload is the best
    assert(y(row) >= lo - 1e-6, "payload is not the best row") end
  assert(i:depth() <= the.depth, "tree grew past depth")
  for _, row in order(te.rows) do          -- every row reaches a leaf,
    assert(i:pick(row), "a row reached no payload")   -- so every row
    assert(i:guess(row) == i:leaf(row).mu) end        -- has an answer
  m1 = mae(te.rows, y, function(row) return i:guess(row) end)
  m2 = mae(te.rows, y, function() return i.mu end)
  print("tree", m1, "grand mean", m2, "depth", i:depth())
  assert(m1 < m2, "tree lost to the grand mean")
  print"PASS tree" end

if (arg and arg[0] or ""):find"tree%.lua$" then
  the = cli()
  run = eg[the.go] or eg.all
  run() end

return _ENV
