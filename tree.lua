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
-- Return the mean diversity `a` and `b` leave behind, weighed by
-- their sizes.  Less is better.  No baseline is wanted, since every
-- candidate cut of a node shares it, and `div` means sd or entropy
-- as the y column asks, so this one line scores either kind.
function val(a,b) --> num
  return (a:div()*a.n + b:div()*b.n) / (a.n + b.n) end

-- Return true when a cut at the `lo`th of `n` rows leaves `the.leaf`
-- of them on both sides.
function big(lo,n) --> bool
  return the.leaf <= lo and lo <= n - the.leaf end

-- Offer `best` every cut of `col` over `xy`, its {x,y} pairs, scored
-- against `tot`, the y summary of all of them.  A SYM has one cut
-- per value.  A NUM has one between each pair of neighbouring
-- distinct x: one sorted pass, growing the left summary, with the
-- right always `tot` less the left and so never built at all.
function SYM.cuts(col,xy,tot,best,    d,b) --> nil
  d = {}
  for _, p in order(xy) do
    b = d[p[1]] or Num(); b:add(p[2]); d[p[1]] = b end
  for v, lhs in pairs(d) do
    if big(lhs.n, #xy) then
      best:add(val(lhs, tot - lhs), {col = col, bin = v}) end end end

function NUM.cuts(col,xy,tot,best,    lhs) --> nil
  table.sort(xy, function(p,q) return p[1] < q[1] end)
  lhs = Num()
  for j, p in order(xy) do
    lhs:add(p[2])
    if j < #xy and p[1] ~= xy[j+1][1] and big(j, #xy) then
      best:add(val(lhs, tot - lhs), {col = col, bin = p[1]}) end end end

-- Return true when `row` is on `cut`'s left.
function left(cut,row) --> bool
  return cut.col:holds(row[cut.col.at], cut.bin) end

-- Return `cut` as text, read going left (`how`=1) or right.
function says(cut,how,    op) --> str
  op = cut.col.it == SYM and {"==", "~="} or {"<=", ">"}
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
function Node(tbl,rows,y,lvl,    i,v,pay) --> NODE
  i   = new(NODE, {tbl = tbl, rows = rows, y = y, lvl = lvl, n = #rows,
                   sub = tbl:clone(rows), all = Num(), ys = {}})
  pay = Best(lt)                        -- the payload: least y so far
  for _, row in order(rows) do
    v = y(row); i.ys[row] = v; i.all:add(v)
    pay:add(v, row) end
  i.row, i.lo, i.mu = pay.has, pay.score, i.all.mu
  return i end

-- Return where to cut `i.rows`: over every x column, every cut it
-- allows, and whichever leaves the least diversity behind.  Column
-- and cut point answer to one test, not two.
function NODE.cut(i,    out,xy,x) --> dict
  out = Best(lt)                     -- least diversity left behind
  for _, col in order(i.sub.x) do
    xy = {}
    for _, row in order(i.rows) do
      x = row[col.at]                -- y is already paid for
      if x ~= "?" then xy[#xy+1] = {x, i.ys[row]} end end
    col:cuts(xy, nums(xy, function(p) return p[2] end), out) end
  return out.has end

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

-- Return how wide `col`'s column has to be: enough for its name,
-- and never so narrow that two columns touch.
function wide(col) --> int
  return max(10, #col.txt + 2) end

-- Return `i`'s goal names, as a header for `goals`.
function NODE.heads(i,    t) --> str
  t = {}
  for k, col in order(i.sub.y) do
    t[k] = ("%" .. wide(col) .. "s"):format(col.txt) end
  return table.concat(t) end

-- Return `i`'s goals: each y column's own mean, in its own units,
-- or its most common value where that column is a SYM.  `mu` and
-- `lo` are one 0..1 distance over all of them; these are the parts.
function NODE.goals(i,    t,v) --> str
  t = {}
  for k, col in order(i.sub.y) do
    v = col.it == NUM and str(col.mu) or best(col.has, same)
    t[k] = ("%" .. wide(col) .. "s"):format(v) end
  return table.concat(t) end

-- Return `i`'s leaves, gathered into `t`, in print order.
function NODE.leaves(i,t) --> list
  t = t or {}
  if i.at then i.left:leaves(t); i.right:leaves(t)
  else         t[#t + 1] = i end
  return t end

-- Return which leaf to tick and which to cross: the lowest and the
-- highest mean `y`.  U+2713 and U+2717 as their utf8 bytes, since
-- luajit is lua 5.1 and has no \u{} escape to write them with.
function NODE.ends(i,    t,out,k) --> dict
  t, out = i:leaves(), {}
  k = best(t, function(node) return  node.mu end)
  out[t[k]] = " \226\156\151 "              -- the worst leaf
  k = best(t, function(node) return -node.mu end)
  out[t[k]] = " \226\156\147 "              -- and the best one
  return out end

-- Print `i`, one line per node: the cut that got us here, how many
-- rows it holds, its mean `y` distance, a mark on the best and the
-- worst leaf, then every goal.  The root call has no cut to name,
-- so that is where the header and the marking go.
function NODE.show(i,s,ends,    pad) --> nil
  if not s then
    ends = i:ends()
    print(("%-26s %5s %6s   %s"):format("", "n", "mu", i:heads())) end
  pad = ("|  "):rep(max(0, i.lvl - 2))       -- the root needs no bar
  print(("%-26s %5d %6s%s%s"):format(
          pad .. (s or ""), i.n, str(i.mu), ends[i] or "   ", i:goals()))
  if i.at then
    i.left:show(says(i.at, 1), ends)
    i.right:show(says(i.at, 2), ends) end
  if not s then print"" end end        -- the root frame ends the tree

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
