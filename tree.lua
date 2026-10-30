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

-- ---- growing ---------------------------------------------------------
-- Return the expected value of the diversity of `a` and `b`.
function val(a,b) --> num
  return (a:div()*a.n + b:div()*b.n) / (a.n + b.n) end

-- True when cutting at the `lo`th of `n` rows feeds both sides.
function big(lo,n) --> bool
  return the.leaf <= lo and lo <= n - the.leaf end

-- Return a tree over `rows` of `tbl:TAB`, scored on `y`.
function Tree(tbl,rows,y) --> NODE
  return Node(tbl, rows or tbl.rows,
                   y or function(row) return tbl:ydist(row) end,
                   1) end

-- Return one node over `rows` -- one pass gets the spread of their
-- `y`s and the payload (the best row seen) -- then, while the cuts
-- stay big enough, its kids.
function Node(tbl,rows,y,lvl,    i,v,pay,cut,a,b,t) --> NODE
  i   = new(NODE, {tbl = tbl, rows = rows, y = y, lvl = lvl, n = #rows,
                   sub = tbl:clone(rows), all = Num(), ys = {}})
  pay = Best(lt)                        -- the payload: least y so far
  for _, row in order(rows) do
    v = y(row); i.ys[row] = v; i.all:add(v)
    pay:add(v, row) end
  i.row, i.lo, i.mu = pay.has, pay.score, i.all.mu
  cut = i.n >= 2*the.leaf and lvl < the.depth and i:cut()
  if cut then
    a, b = {}, {}
    for _, row in order(rows) do
      t = cut.col:holds(row[cut.col.at], cut.bin) and a or b
      t[#t + 1] = row end
    if #a >= the.leaf and #b >= the.leaf then   -- else, a bad cut
      i.at   = cut
      i.left, i.right = Node(tbl, a, y, lvl+1), Node(tbl, b, y, lvl+1)
    end end
  return i end

-- Return the cut of `i.rows` -- a column, and a value where that
-- column splits -- leaving the least y diversity behind: one cut per
-- SYM value; for NUMs, one between each distinct sorted neighbour,
-- with the right-hand summary always `tot` less the left.
function NODE.cut(i,    out,xy,x,tot,d,b,lhs) --> dict
  out = Best(lt)                     -- least diversity left behind
  for _, col in order(i.sub.x) do
    xy, tot = {}, Num()            -- y is already paid for; one
    for _, row in order(i.rows) do -- pass fills xy and sums it
      x = row[col.at]
      if x ~= "?" then xy[#xy+1] = {x=x, y=tot:add(i.ys[row])} end end
    if col.it == SYM then
      d = {}
      for _, p in order(xy) do
        b = d[p.x] or Num(); b:add(p.y); d[p.x] = b end
      for v, lhs in pairs(d) do
        if big(lhs.n, #xy) then
          out:add(val(lhs, tot - lhs), {col = col, bin = v}) end end
    else
      sort(xy, "x")
      lhs = Num()
      for j, p in order(xy) do
        lhs:add(p.y)
        if j < #xy and p.x ~= xy[j+1].x and big(j, #xy) then
          out:add(val(lhs, tot-lhs), {col = col, bin = p.x}) end end
    end end
  return out.has end

-- ---- asking ----------------------------------------------------------
-- Return the mean absolute error of `fn` against `y` over `rows`.
function mae(rows,y,fn,    err) --> num
  err = function(row) return abs(y(row) - fn(row)) end
  return nums(rows, err).mu end

-- Return the leaf `row` falls into: its `mu` is the guess for
-- `row`, and its `row` the payload -- the best labelled row there.
function NODE.pick(i,row,    c) --> NODE
  if not i.at then return i end
  c = i.at
  return (c.col:holds(row[c.col.at], c.bin) and i.left
          or i.right):pick(row) end

-- Return one cell per y column -- `f(col)` -- padded to fit.
function NODE.ycols(i,f,    t) --> str
  t = {}
  for k, col in order(i.sub.y) do
    t[k] = ("%" .. max(10, #col.txt + 2) .. "s"):format(f(col)) end
  return table.concat(t) end

-- Call `f(node,s)` on `i` and everything below, pre-order; `s` is
-- the cut that got us to each node ("" at the root).
function NODE.walk(i,f,s,    c,op) --> nil
  f(i, s or "")
  c = i.at
  if c then
    op = c.col.it == SYM and {"==", "~="} or {"<=", ">"}
    i.left:walk(f, c.col.txt.." "..op[1].." "..str(c.bin))
    i.right:walk(f, c.col.txt.." "..op[2].." "..str(c.bin)) end end

-- Print `i`, one line per node, ticking the best leaf and crossing
-- the worst (as utf8 bytes: lua 5.1 has no \u{} escape).
function NODE.show(i,    t,ends,cell) --> nil
  cell = function(col)
    return col.it == NUM and str(col.mu) or best(col.has, same) end
  t, ends = {}, {}
  i:walk(function(n) if not n.at then t[#t + 1] = n end end)
  sort(t, "mu")
  ends[t[#t]] = " \226\156\151 "            -- cross the worst leaf,
  ends[t[1]]  = " \226\156\147 "            -- tick the best one
  print(("%-26s %5s %6s   %s"):format("", "n", "mu",
        i:ycols(function(col) return col.txt end)))
  i:walk(function(n,s)
    print(("%-26s %5d %6s%s%s"):format(
            ("|  "):rep(max(0, n.lvl - 2)) .. s,   -- root gets no bar
            n.n, str(n.mu), ends[n] or "   ", n:ycols(cell))) end)
  print"" end

-- ---- start up --------------------------------------------------------
-- Return `the.file` as train and test TABs, plus a `y` scored off
-- the train table alone (all a learner is allowed to see).
function halves(    tbl,tr,te) --> TAB
  tbl    = Tab(the.file)
  tr, te = tbl:split()
  tr, te = tbl:clone(tr), tbl:clone(te)
  return tr, te, function(row) return tr:ydist(row) end end

function eg.tree(    tr,te,y) --> nil
  tr, te, y = halves()
  Tree(tr, tr.rows, y):show() end

function eg.all(    tr,te,y,i,lo,m1,m2,d) --> nil
  tr, te, y = halves()
  i  = Tree(tr, tr.rows, y)
  assert(i.n == #tr.rows, "root holds every training row")
  lo = i.lo
  for _, row in order(tr.rows) do          -- the payload is the best
    assert(y(row) >= lo - 1e-6, "payload is not the best row") end
  d = 0
  i:walk(function(n) d = max(d, n.lvl) end)
  assert(d <= the.depth, "tree grew past depth")
  for _, row in order(te.rows) do          -- every row reaches a
    assert(i:pick(row).row, "a row reached no payload") end -- leaf
  m1 = mae(te.rows, y, function(row) return i:pick(row).mu end)
  m2 = mae(te.rows, y, function() return i.mu end)
  print("tree", m1, "grand mean", m2, "depth", d)
  assert(m1 < m2, "tree lost to the grand mean")
  print"PASS tree" end

if (arg and arg[0] or ""):find"tree%.lua$" then
  the = cli()
  run = eg[the.go] or eg.all
  run() end

return _ENV
