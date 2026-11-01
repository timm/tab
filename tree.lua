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

NODE, lab = {}, {}      -- lab[the.go]() runs at start up

usage = [[
flags:
  depth=4          how deep the tree may grow
  leaf=8           rows each side of a cut needs
  go=all           which action to run
]]
for k, v in usage:gmatch"\n%s+(%a+)=(%S+)" do the[k] = values(v)[1] end

function least(    it,b4) --> fun; a collector of the least thing it is
  return function(score,payload)
    if score ~= nil and (b4 == nil or score < b4) then
      it, b4 = payload, score end
    return it, b4 end end

-- ---- growing ---------------------------------------------------------
function Tree(tbl,rows,y,Y) --> NODE; a tree over `rows` of `tbl:TAB`,
  return Node(tbl, rows or tbl.rows,
                   y or function(row) return tbl:ydist(row) end,
                   1, Y or Num) end

function Node(tbl,rows,y,lvl,Y,    i,v,pay,all,cut,a,b,t,op) --> NODE; one
  i   = new(NODE, {tbl = tbl, rows = rows, y = y, lvl = lvl, Y = Y,
                   n = #rows, sub = tbl:clone(rows), ys = {}, txt = ""})
  all, pay = Y(), Y == Num and least()   -- a klass has no best row
  for _, row in order(rows) do
    v = y(row); i.ys[row] = v; all:add(v)
    if pay then pay(v, row) end end
  i.all = all
  i.row = pay and pay()
  i.mu  = all.mu or best(all.has, same)   -- a mean, or a majority
  cut = i.n >= 2*the.leaf and lvl < the.depth and i:cut()
  if cut then
    a, b = {}, {}
    for _, row in order(rows) do
      t = cut.col:holds(row[cut.col.at], cut.bin) and a or b
      t[#t + 1] = row end
    if #a >= the.leaf and #b >= the.leaf then   -- else, a bad cut
      i.at = cut
      i.left  = Node(tbl, a, y, lvl+1, Y)
      i.right = Node(tbl, b, y, lvl+1, Y)
      op = cut.col.it == SYM and {"==", "~="} or {"<=", ">"}
      i.left.txt  = cut.col.txt.." "..op[1].." "..o(cut.bin)
      i.right.txt = cut.col.txt.." "..op[2].." "..o(cut.bin) end end
  return i end

function NODE.cut(i,    out,xy,x,tot,d,b,lhs,val,big) --> dict; cut of
  function val(a,b)  return (a:div()*a.n + b:div()*b.n) / (a.n+b.n) end
  function big(lo,n) return the.leaf <= lo and lo <= n - the.leaf end
  out = least()                      -- least diversity left behind
  for _, col in order(i.sub.x) do
    xy, tot = {}, i.Y()            -- y is already paid for; one
    for _, row in order(i.rows) do -- pass fills xy and sums it
      x = row[col.at]
      if x ~= "?" then xy[#xy+1] = {x=x, y=tot:add(i.ys[row])} end end
    if col.it == SYM then
      d = {}
      for _, p in order(xy) do
        b = d[p.x] or i.Y(); b:add(p.y); d[p.x] = b end
      for v, lhs in pairs(d) do
        if big(lhs.n, #xy) then
          out(val(lhs, tot - lhs), {col = col, bin = v}) end end
    else
      sort(xy, "x")
      lhs = i.Y()
      for j, p in order(xy) do
        lhs:add(p.y)
        if j < #xy and p.x ~= xy[j+1].x and big(j, #xy) then
          out(val(lhs,tot-lhs),{col=col,bin=p.x}) end end end end
  return (out()) end

-- ---- asking ----------------------------------------------------------
function NODE.pick(i,row,    c) --> NODE; leaf `row` falls into: its `mu`
  if not i.at then return i end
  c = i.at
  return (c.col:holds(row[c.col.at], c.bin) and i.left or i.right)
         :pick(row) end

function NODE.ycols(i,f,    t) --> str; one cell per y column -- `f(col)`
  t = {}
  for k, col in order(i.sub.y) do
    t[k] = ("%" .. max(10, #col.txt + 2) .. "s"):format(f(col)) end
  return table.concat(t) end

function NODE.walk(i,    todo) --> fun; an iterator over `i` and everything
  todo = {i}
  return function(    n)
    n = table.remove(todo)
    if not n then return end
    if n.at then todo[#todo+1] = n.right; todo[#todo+1] = n.left end
    return n end end

function NODE.show(i,    t,ends,cell,n) --> nil; print `i`, one line per
  cell = function(col)
    return col.it == NUM and o(col.mu) or best(col.has, same) end
  t, ends = {}, {}
  for n in i:walk() do
    if not n.at then t[#t + 1] = n end end
  sort(t, "mu")
  ends[t[#t]] = " \226\156\151 "            -- cross the worst leaf,
  ends[t[1]]  = " \226\156\147 "            -- tick the best one
  print(("%-26s %5s %6s   %s"):format("", "n", "mu",
        i:ycols(function(col) return col.txt end)))
  for n in i:walk() do
    print(("%-26s %5d %6s%s%s"):format(
            ("|  "):rep(max(0, n.lvl-2)) .. n.txt, -- root gets no bar
            n.n, o(n.mu), ends[n] or "   ", n:ycols(cell))) end
  print"" end

-- ---- predicting ------------------------------------------------------
function NODE.posts(i,row,    n,t) --> dict; p(klass | `row`) off the leaf
  n, t = i:pick(row), {}
  for k, m in pairs(n.all.has) do t[k] = m / n.all.n end
  return t end

function NODE.nb(i) --> NB; leaf's own naive Bayes, fitted the first time
  i.model = i.model or Nb(i.sub, i.rows)
  return i.model end

-- ---- start up --------------------------------------------------------
function halves(    tbl,tr,te) --> TAB; `the.file` as train and test TABs,
  tbl    = Tab(the.file)
  tr, te = tbl:split()
  tr, te = tbl:clone(tr), tbl:clone(te)
  return tr, te, function(row) return tr:ydist(row) end end

function lab.tree(    tr,te,y) --> nil
  tr, te, y = halves()
  Tree(tr, tr.rows, y):show() end

function lab.all(    tr,te,y,i,lo,m1,m2,d,err,n) --> nil
  tr, te, y = halves()
  i  = Tree(tr, tr.rows, y)
  assert(i.n == #tr.rows, "root holds every training row")
  lo = y(i.row)
  for _, row in order(tr.rows) do          -- the payload is the best
    assert(y(row) >= lo - 1e-6, "payload is not the best row") end
  d = 0
  for n in i:walk() do d = max(d, n.lvl) end
  assert(d <= the.depth, "tree grew past depth")
  for _, row in order(te.rows) do          -- every row reaches a
    assert(i:pick(row).row, "a row reached no payload") end -- leaf
  err = function(fn)                      -- mean error of a guess
          return nums(te.rows, function(row)
                   return abs(y(row) - fn(row)) end).mu end
  m1 = err(function(row) return i:pick(row).mu end)
  m2 = err(function() return i.mu end)
  print("tree", m1, "grand mean", m2, "depth", d)
  assert(m1 < m2, "tree lost to the grand mean")
  n = least()                              -- what every cut runs on
  for _, v in ipairs{3, 9, 1, 5} do n(v, "row" .. v) end
  assert(n() == "row1" and select(2, n()) == 1)
  assert(least()() == nil)                 -- offered nothing, holds
  print"PASS tree" end

if (arg and arg[0] or ""):find"tree%.lua$" then
  the = cli()
  run = lab[the.go] or lab.all
  run() end

return _ENV
