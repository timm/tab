#!/usr/bin/env lua
-- <!--- vim: set ts=2 sw=2 sts=2 et cc=75 : -->
local _ENV = setmetatable({}, {__index = _G})
if setfenv then setfenv(1, _ENV) end   -- lua 5.1, luajit

the,help = {}, [[
tab.lua: a good guess from a few dozen labels.
Range means, shrunk to the grand mean, weighed by variance.
(c) 2026 Tim Menzies <timm@ieee.org> MIT license.

usage: lua tab.lua [name=value | action | file.csv ...]

flags:
  version=0.6.0    version number
  bins=7           numeric columns get this many bins
  budge=50         a fast test over this many ms belongs in slow
  budget=50        labels, all in
  check=5          of those, saved for the test rows
  fmt=%.2f         how a fraction is printed
  depth=4          how deep a tree may grow
  leaf=8           rows each side of a cut needs
  m=2              m-estimate: prior weight for a thin bin
  p=2              minkowski coefficient
  reps=3           repeats, when something is timed
  seed=1234567891  random number seed
  test=None        held-out csv (None: demos test on train)
  train=~/gits/moot/optimize/misc/auto93.csv

actions:
   -h              print help
   --all           every fast action (--num, --split ... run one)

Any flag above can lead an action, so `seed=1 --split` is a thing.]]

floor, exp, sqrt, log = math.floor, math.exp, math.sqrt, math.log
abs, min, max = math.abs, math.min, math.max

TAB,NUM,SYM,RMEANS,NB,TREE = {},{},{},{},{},{}

-- ---- values ---------------------------------------------------------
function values(s,   u,v) --> row; values from comma-separated `s`.
  u = {}
  for s1 in (s .. ","):gmatch"(.-)," do
    v = s1:match"^%s*(.-)%s*$"
    u[#u + 1] = tonumber(v) or v end
  return u end

function csv(file,   rows,s) --> rows; `rows` in a `file:str`.
  rows = {}
  for line in io.lines((file:gsub("^~", os.getenv"HOME" or "~"))) do
    s = line:match"^%s*(.-)%s*$"
    if s ~= "" and s:sub(1, 1) ~= "#" then
      rows[#rows + 1] = values(s) end end
  return rows end

-- ---- columns ---------------------------------------------------------
function Col(txt,at) --> SYM | NUM; a-z Sym; A-Z Num.
   return (txt:find"^%u" and Num or Sym)(txt, at) end

function Sym(txt,at) --> SYM; counts of symbols seen in column `at`.
  return new(SYM, {txt = txt or "S", at = at or 0, n = 0, has = {}}) end

function SYM.add(i,v,inc) --> value; `inc` more of `v` (-1 = one less).
  if v == "?" then return v end
  inc = inc or 1
  i.n = i.n + inc
  i.has[v] = (i.has[v] or 0) + inc
  if i.has[v] <= 0 then i.has[v] = nil end
  return v end

function SYM.div(i,    fn) --> num; entropy, in bits.
  fn = function(n) return -n/i.n * log(n/i.n) end
  return sum(i.has, fn) / log(2) end

function SYM.mid(i) return (best(i.has, same)) end --> value; the mode.
function SYM.norm(i,v) return v end --> value; a sym is its own norm
function SYM.holds(i,x,v) return x == "?" or x == v end --> bool
function SYM.bin(i,v) return v end --> value; and its own bin

function SYM.cut(i,xy,Y,out,    d,near,far) --> one cut per symbol
  d = {}
  for _, p in order(xy) do d[p.x] = (d[p.x] or 0) + 1 end
  for v, _ in pairs(d) do
    near, far = Y(), Y()
    for _, p in order(xy) do
      (p.x == v and near or far):add(p.y) end
    out(near, far, v) end end

function SYM.nVals(i) --> int; how many values `i` has seen, at least 2.
  i.kinds = i.kinds or max(2, sum(i.has, function() return 1 end))
  return i.kinds end

function Num(txt,at) --> NUM; Welford summary of numbers in column `at`.
  return new(NUM, {txt = txt or "N", at = at or 0, n = 0, mu = 0, m2 = 0,
                   w = (txt or ""):find"%-$" and 0 or 1}) end

function NUM.add(i,v,inc,    d) --> value; `inc` more of `v` (-1 takes
  if v == "?" then return v end         -- it back out, so one scan can
  inc = inc or 1                        -- shift rows across a cut)
  i.n = i.n + inc
  if i.n <= 0 then i.n, i.mu, i.m2 = 0, 0, 0; return v end
  d    = v - i.mu
  i.mu = i.mu + inc * d / i.n
  i.m2 = i.m2 + inc * d * (v - i.mu)
  return v end

function NUM.div(i) return i.n<2 and 0 or sqrt(max(i.m2,0)/(i.n - 1)) end
function NUM.mid(i) return i.mu end --> num; the mean
function NUM.holds(i,x,v) return x == "?" or x <= v end --> bool; "?"

function NUM.bin(i,v,    b) --> value; `v`'s bin, 1..`the.bins`.
  if v == "?" then return v end
  b = 1 + floor(the.bins * i:norm(v))
  return b > the.bins and the.bins or b end

function NUM.norm(i,v,    z) --> value; `v` on a logistic cdf, clipped
  if v == "?" then return v end        -- at three standard deviations
  z = (v - i.mu) / (i:div() + 1e-32)
  z = z > 3 and 3 or (z < -3 and -3 or z)
  return 1 / (1 + exp(-1.7 * z)) end

                                 -- says yes, so a cut never loses a row
-- Offer `out` one cut between each pair of distinct sorted neighbours:
-- sort once, grow `near` left to right while `far` sheds the same.
function NUM.cut(i,xy,Y,out,    near,far)
  sort(xy, "x")
  near, far = Y(), Y()
  for _, p in order(xy) do far:add(p.y) end
  for j, p in order(xy) do
    near:add(p.y); far:add(p.y, -1)
    if j < #xy and p.x ~= xy[j+1].x then out(near, far, p.x) end end end

-- ---- tables ----------------------------------------------------------
function Tab(src) --> TAB; a TAB from `src`: a file name, or rows.
  return adds(src, new(TAB, {rows={}, names={}, cols={}, x={}, y={}})) end

function TAB.add(i,row) --> row; the first `row` is the names.
  if #i.cols == 0 then return i:head(row) end
  i.rows[#i.rows + 1] = row
  for _, col in order(i.cols) do col:add(row[col.at]) end
  return row end

function TAB.head(i,names,    col) --> nil; read `names:row` as `i`'s
  i.names = names                   -- columns: X skip, -+! goals,
  for at, txt in order(names) do    -- ! the klass, - minimize
    col = Col(txt, at)
    i.cols[#i.cols + 1] = col
    if     txt:find"X$"     then
    elseif txt:find"[-+!]$" then i.y[#i.y + 1] = col
      if txt:find"!$" then i.klass = col end
    else i.x[#i.x + 1] = col end end end

function TAB.clone(i,rows,how,    out) --> TAB; `rows` in a fresh TAB
  out = {how and map(i.cols, function(col) return col.txt:lower() end)
             or i.names}         -- `how`="bin" discretizes, so sym
  for _, row in order(rows or {}) do
    out[#out + 1] = not how and row or map(i.cols,
      function(col) return col[how](col, row[col.at]) end) end
  return Tab(out) end

function TAB.mid(i,cols,    fn) --> dict; {name: middle}, for logfmt.
  fn = function(c) u[c.txt] = c:mid() end
  return map(cols or i.cols, fn) wns

function TAB.ydist(i,row,    fn) --> num; `row`'s distance to heaven
  fn = function(col) return abs(col:norm(row[col.at]) - col.w)^the.p end
  return (sum(i.y, fn) / #i.y) ^ (1 / the.p) end

function TAB.split(i,    rows,n,t,u1,u2) --> rows,rows; 80:20, off a
  rows   = shuffle(map(i.rows, same))    -- copy: never i.rows itself
  n      = floor(.8 * #rows)
  u1, u2 = {}, {}; t = u1
  for j,row in order(rows) do if j>n then t = u2 end; t[#t+1] = row end
  return u1, u2 end

-- Offer `out` every cut of every x column over `rows`: `ys` is one
-- y per row; `Y` collects them, so what "least diversity" means --
-- Num and sd, or Sym and entropy -- is the caller's choice.
function TAB.cut(i,rows,ys,Y,out,    xy,x,offer,col1)
  Y = Y or (type(ys[1]) == "string" and Sym or Num)
  offer = function(near,far,v)  -- the one scorer and leaf guard, for
    if near.n >= the.leaf and far.n >= the.leaf then  -- every column
      out((near:div()*near.n + far:div()*far.n) / (near.n + far.n),
          {col = col1, v = v}) end end
  for _, col in order(i.x) do
    col1 = col
    xy = {}
    for k, row in order(rows) do
      x = row[col.at]
      if x ~= "?" then xy[#xy + 1] = {x = x, y = ys[k]} end end
    col:cut(xy, Y, offer) end
  return out end

-- ---- rmeans ----------------------------------------------------------
function Rmeans(tbl,rows,y,    i,sub,bins,b,w,fn) --> RMEANS; per x
  i   = new(RMEANS, {all = Num(), has = {}})  -- column, its bins' y
  sub = tbl:clone(rows)                 -- means and the variance cut
  i.cols = sub.x
  adds(sub.rows, i.all, y)
  for _, col in order(sub.x) do
    bins = {}
    for _, row in order(sub.rows) do
      b = col:bin(row[col.at])
      bins[b] = bins[b] or Num()
      bins[b]:add(y(row)) end
    fn = function(v) return v.n/i.all.n * v:div() ^ 2 end
    w  = i.all:div() ^ 2 - sum(bins, fn)
    i.has[col.at] = {bins = bins, w = max(0, w)} end
  return i end

function RMEANS.like(i,col,row,    it,v) --> num,num; `col`'s
  it = i.has[col.at]    -- m-estimated guess for `row`, and its worth
  v  = it and it.bins[col:bin(row[col.at])]
  if v and it.w > 0 then
    return (v.n * v.mu + the.m * i.all.mu) / (v.n + the.m), it.w end end

function RMEANS.guess(i,row,    s,w,g,wt) --> num; `row`'s guess: the
  s, w = 0, 0           -- worth-weighted mean of every column's like
  for _, col in order(i.cols) do
    g, wt = i:like(col, row)
    if g then s, w = s + wt * g, w + wt end end
  return w > 0 and s / w or i.all.mu end

-- ---- bayes -----------------------------------------------------------
function Nb(tbl,rows,    i,v) --> NB; one sub-TAB per klass in `rows`.
  i = new(NB, {tbl = tbl, subs = {}, n = #rows, nKlass = 0})
  for _, row in order(rows) do
    v = row[tbl.klass.at]
    if not i.subs[v] then
      i.subs[v], i.nKlass = tbl:clone(), i.nKlass + 1 end
    i.subs[v]:add(row) end
  return i end

function NB.like(i,sub,row,    fn) --> num; log P(`row` | `sub:TAB`)
  fn = function(col1,at,    col,v)
        col, v = i.tbl.x[at], row[col1.at] -- col knows every value;
        if v == "?" then return 0 end      -- col1 knows this klass's
        return log(((col1.has[v] or 0) + the.m)    -- and m per value
                   / (col1.n + the.m * col:nVals())) end
  return log((#sub.rows + the.m) / (i.n + the.m * i.nKlass)) -- m/klass
         + sum(sub.x, fn) end

function NB.guess(i,row,    fn) --> value; `row`'s likeliest klass.
  fn = function(sub) return i:like(sub, row) end
  return (best(i.subs, fn)) end

-- ---- tree ----------------------------------------------------------
function Tree(tbl,rows,y,Y,lvl,    i,v,pay,all,cut,a,b,t,op) --> TREE;
  rows = rows or tbl.rows             -- one node over `rows`, then,
  y    = y or function(row) return tbl:ydist(row) end  -- while the
  Y    = Y or Num                     -- cuts stay big enough, kids
  lvl  = lvl or 1
  i   = new(TREE, {tbl = tbl, rows = rows, y = y, lvl = lvl, Y = Y,
                   n = #rows, sub = tbl:clone(rows), ys = {}, txt = ""})
  all, pay = Y(), Y == Num and argmin()   -- a klass has no best row
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
      t = cut.col:holds(row[cut.col.at], cut.v) and a or b
      t[#t + 1] = row end
    if #a >= the.leaf and #b >= the.leaf then   -- else, a bad cut
      i.at = cut
      i.left  = Tree(tbl, a, y, Y, lvl+1)
      i.right = Tree(tbl, b, y, Y, lvl+1)
      op = cut.col.it == SYM and {"==", "~="} or {"<=", ">"}
      i.left.txt  = cut.col.txt.." "..op[1].." "..o(cut.v)
      i.right.txt = cut.col.txt.." "..op[2].." "..o(cut.v) end end
  return i end

function TREE.cut(i,    ys) --> dict; the cut of `i.rows` leaving
  ys = map(i.rows, function(row) return i.ys[row] end) -- the least
  return (i.sub:cut(i.rows, ys, i.Y, argmin())()) end  -- y diversity

-- ---- asking ----------------------------------------------------------
function TREE.pick(i,row,    c) --> TREE; leaf `row` falls into: its `mu`
  if not i.at then return i end
  c = i.at
  return (c.col:holds(row[c.col.at], c.v) and i.left or i.right)
         :pick(row) end

function TREE.ycols(i,f,    t) --> str; one cell per y column -- `f(col)`
  t = {}
  for k, col in order(i.sub.y) do
    t[k] = ("%" .. max(10, #col.txt + 2) .. "s"):format(f(col)) end
  return table.concat(t) end

function TREE.walk(i,    todo) --> fun; an iterator over `i` and everything
  todo = {i}
  return function(    n)
    n = table.remove(todo)
    if not n then return end
    if n.at then todo[#todo+1] = n.right; todo[#todo+1] = n.left end
    return n end end

function TREE.show(i,    t,ends,cell,n) --> nil; print `i`, one line per
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

-- Return `i` as nested tables: this node's n, mu, split and y-column
-- centers, then its two kids under `left` and `right`.  So `logfmt`
-- prints the whole tree as a record a later run can be diffed against.
function TREE.dict(i,    t) --> dict
  t = {n = i.n, mu = i.mu}
  if i.txt ~= "" then t.txt = i.txt end
  for _, col in order(i.sub.y) do
    t[col.txt] = col.it == NUM and col.mu or best(col.has, same) end
  if i.at then
    t.left, t.right = i.left:dict(), i.right:dict() end
  return t end

-- ---- predicting ------------------------------------------------------
function TREE.posts(i,row,    n,t) --> dict; p(klass | `row`) off the leaf
  n, t = i:pick(row), {}
  for k, m in pairs(n.all.has) do t[k] = m / n.all.n end
  return t end

function TREE.nb(i) --> NB; leaf's own naive Bayes, fitted the first time
  i.model = i.model or Nb(i.sub, i.rows)
  return i.model end


-- ---- misc ---------------------------------------------------------
function new(meta,i) --> inst; connect instance `i` to its class `meta`;
  meta.__index, meta.it, meta.__tostring = meta, meta, o
  return setmetatable(i, meta) end

function cli(    k,v) --> dict; update `the` from the command line: a
  for _, s in order(arg) do        -- name=value, action, file
    k, v = s:match"^(%a%w*)=(.*)$"
    if     k               then the[k] = values(v)[1]
    elseif eg[s] or slow[s] then (eg[s] or slow[s])()
    else                       the.file = s end end
  return the end

-- Restart the generator at `n`, or back at `the.seed`.  The setting
-- and the state are two things: `the.seed` says where a run began,
-- `rng` is where it has got to, so a header can still name the seed.
function seed(n) --> nil
  rng = n or the.seed end

function rint(n) --> int; an int in 1..`n`, repeatable from `the.seed`.
  rng = (16807 * (rng or the.seed)) % 2147483647
  return 1 + floor(n * rng / 2147483647) end

function shuffle(t,    j) --> list; `t`, Fisher-Yates shuffled in place.
  for k = #t, 2, -1 do j = rint(k); t[k], t[j] = t[j], t[k] end
  return t end

function map(t,fn,    u) --> list; `fn(v,k)` over `t`, nils dropped.
  u={}; for k, v in ipairs(t) do u[#u+1] = fn(v, k) end
  return u end

function sum(t,fn,    n) --> num; `fn(v,k)` over every item, added up.
  n=0; for k, v in pairs(t) do n = n + fn(v, k) end; return n end

function adds(src,it,fn) --> it; `fn(x)` for x in `src`, added to `it`
  it, fn = it or Num(), fn or same    -- (a fresh Num, by default)
  for _, x in order(src) do it:add(fn(x)) end
  return it end

function best(t,fn,    n,m,u) --> any,num; key of `t` with the biggest
  for k, v in pairs(t) do             -- `fn(v,k)`, and that score
    m = fn(v, k)
    if not n or m > n then n, u = m, k end end
  return u, n end

function argmin(    it,b4) --> fun; collect the least thing offered.
  return function(score,payload)      -- call with (score, thing) to
    if score ~= nil and (b4 == nil or score < b4) then  -- offer; with
      it, b4 = payload, score end     -- nothing, to ask what won
    return it, b4 end end

function same(x) return x end --> any

function lt(a,b) return a < b end --> bool

function sort(t,fn,    k) --> list; `t` sorted in place, ascending.
  if fn and type(fn) ~= "function" then  -- `fn`: comparator, or a key
    k = fn; fn = function(a,b) return a[k] < b[k] end end
  table.sort(t, fn)
  return t end

function order(t,fn) --> fun; `ipairs(t)` (or of a sorted copy, given
  if type(t) == "string" then t = csv(t) end  -- `fn`); a string `t`
  if not fn then return ipairs(t) end         -- means rows of a csv
  return ipairs(sort(map(t, same), fn)) end

function o(x,    u) --> str; `x` as text: fractions through `the.fmt`,
  if type(x) ~= "table" then
    if type(x) ~= "number" then return tostring(x) end
    return tostring(x == floor(x) and floor(x) or the.fmt:format(x)) end
  u = {}
  if #x>0 then for _, v in ipairs(x) do u[#u+1] = o(v) end
          else for k, v in pairs(x) do
                 if k ~= "it" and type(v) ~= "function" then
                   u[#u + 1] = o(k) .. "=" .. o(v) end end end
  return "{"..table.concat(#x > 0 and u or sort(u, lt)," ").."}" end

function print(...) --> nil; print the lot, tab separated, through `o`.
  local out = {}
  for j = 1, select("#", ...) do out[j] = o((select(j, ...))) end
  io.write(table.concat(out, "\t"), "\n") end

function fmt(s,...) return s:format(...) end --> str

-- Return `d:dict` as "k=v k=v" lines, keys sorted.  Atoms pack onto
-- one line; a table value gets its key, then its own lines, indented
-- one more stop.  So a nested dict prints as deep as it really is.
function logfmt(d,indent,    pad,u,flat,out) --> str
  pad, u, flat, out = ("  "):rep(indent or 0), {}, {}, {}
  for k in pairs(d) do u[#u + 1] = k end
  sort(u)
  for _, k in order(u) do
    if type(d[k]) ~= "table" then
      flat[#flat + 1] = k .. "=" .. o(d[k]) end end
  if #flat > 0 then out[1] = pad .. table.concat(flat, " ") end
  for _, k in order(u) do
    if type(d[k]) == "table" then
      out[#out + 1] = pad .. k
      out[#out + 1] = logfmt(d[k], (indent or 0) + 1) end end
  return table.concat(out, "\n") end

-- Say what this run was: when it ran, which version ran it, what it
-- was asked, and every setting in play.  An eg prints this above its
-- results, so a result read a year later knows where it came from.
function about(    t) --> nil
  print":config"
  t = {date = os.date"%Y-%m-%d %H:%M:%S", version = the.version,
       cmd  = (arg and arg[0] or "?")
              .. (arg and #arg > 0
                  and " " .. table.concat(arg, " ") or "")}
  print(logfmt(t))
  print(logfmt(the)) end
-- ---- tests --------------------------------------------------------
-- Demos double as tests: each prints a little, asserts golden values.
-- Port tab to another language, pass these, and the port agrees with
-- this code to 1e-6.  `eg` run under --all; `slow` only when named.
eg, slow = {}, {}

function near(a,b) return abs(a - b) < 1e-6 end --> bool

function ok(got,want) --> any; assert `got` is `want`, then return it.
  assert(got == want or (type(got) == "number" and
         type(want) == "number" and near(got, want)),
         o(got) .. " ~= " .. o(want))
  return got end

function run(k) --> nil; a :name header, then the action.
  print(":" .. k:gsub("^%-+", ""))
  seed(); (eg[k] or slow[k])() end

eg["-h"] = function() print(help) end

eg["--all"] = function(    keys,t0,ms,worst,who)
  worst = 0
  keys = {}
  for k in pairs(eg) do
    if not (" -h --all "):find(" " .. k .. " ", 1, true) then
      keys[#keys + 1] = k end end
  for _, k in order(keys, lt) do
    t0 = os.clock()
    run(k)
    ms = (os.clock() - t0) * 1000
    if ms > worst then worst, who = ms, k end end
  print(fmt("PASS %s tests, worst %s at %.1fms", #keys, who, worst)) end

slow["--secs"] = function(    file,tbl,tot,t0,tr,te,sub,y,lim,few)
  file = the.file or the.train      -- time rmeans: train, then guess
  tbl, tot = Tab(file), 0
  for r = 1, the.reps do
    seed(the.seed + r)
    tr, te = tbl:split()
    sub = tbl:clone(tr)
    y   = function(row) return sub:ydist(row) end
    lim = the.budget - the.check
    t0  = os.clock()
    few = {}
    for j = 1, (#tr < lim and #tr or lim) do few[j] = tr[j] end
    local model = Rmeans(tbl, few, y)
    for _, row in order(te) do model:guess(row) end
    tot = tot + (os.clock() - t0) end
  print(fmt("%s rows=%6d secs=%.4f",
            file:match"([^/]+)%.csv$", #tbl.rows, tot / the.reps)) end

eg["--values"] = function(    t)
  t = values" 4.2, x,3"
  print(logfmt{got = o(t)})
  ok(t[1], 4.2); ok(t[2], "x"); ok(t[3], 3) end

eg["--csv"] = function(    t)
  t = csv(the.train)
  print(logfmt{rows = #t, cells = #t[1]})
  ok(#t, 399); ok(#t[1], 8); ok(t[1][1], "Clndrs") end

eg["--num"] = function(    n)
  n = adds{1,2,3,4,5,6,7,8,9,10}
  print(logfmt{mu = n:mid(), sd = n:div()})
  ok(n:div(), 3.0276503541) end

eg["--sym"] = function(    s)
  s = adds({"a","a","b","c","c","c"}, Sym())
  print(logfmt{mode = s:mid(), ent = s:div()})
  ok(s:div(), 1.4591479170) end

eg["--tab"] = function(    t)
  t = Tab(the.train)
  print(logfmt{rows = #t.rows, x = #t.x, y = #t.y})
  ok(#t.rows, 398); ok(#t.x, 4); ok(#t.y, 3) end

eg["--mid"] = function(    t)
  t = Tab(the.train)
  print(logfmt(t:mid(t.y)))
  ok(t:mid(t.y)["Acc+"], 15.5680904523) end

eg["--ydist"] = function(    t)
  t = Tab(the.train)
  print(logfmt{guzzler = t:ydist(t.rows[1]),
               honda   = t:ydist(t.rows[398])})
  ok(t:ydist(t.rows[1]),   0.7863215821)
  ok(t:ydist(t.rows[398]), 0.1410148526) end

eg["--split"] = function(    t,tr,te)
  t = Tab(the.train)
  tr, te = t:split()
  print(logfmt{train = #tr, test = #te})
  ok(#tr, 318); ok(#te, 80)
  ok(table.concat(tr[1], ","), "6,145,76,81,2,3160,19.6,30")
  ok(t.rows[1][1], 8) end         -- t.rows itself was not disturbed

eg["--cut"] = function(    t,ys,it,v) -- least-sd cut of auto93
  t  = Tab(the.train)
  ys = map(t.rows, function(row) return t:ydist(row) end)
  it = t:cut(t.rows, ys, Num, argmin())
  print(logfmt{col = it().col.txt, v = it().v})
  ok(it().col.txt, "Volume"); ok(it().v, 262)
  ok(select(2, it()), 0.1431540929) end

eg["--rmeans"] = function(    t,y,few,m)
  t, few = Tab(the.train), {}
  y = function(row) return t:ydist(row) end
  for k = 1, 45 do few[k] = t.rows[k] end
  m = Rmeans(t, few, y)
  print(logfmt{mu = m.all.mu, guess = m:guess(t.rows[1])})
  ok(m.all.mu,          0.9009519530)
  ok(m:guess(t.rows[1]), 0.8530303902) end

eg["--nb"] = function(    t,b,i)
  t = Tab{{"Age", "job", "klass!"},
          {20, "low", "no"},  {22, "low", "no"}, {25, "low", "no"},
          {30, "med", "no"},  {60, "hi", "yes"}, {62, "hi", "yes"},
          {65, "med", "yes"}, {70, "hi", "yes"}}
  b = t:clone(t.rows, "bin")
  i = Nb(b, b.rows)
  print(logfmt{young = i:guess(b.rows[1]), old = i:guess(b.rows[8])})
  ok(i:guess(b.rows[1]), "no"); ok(i:guess(b.rows[8]), "yes") end

eg["--logfmt"] = function(    s)
  s = logfmt{seed = 1, go = "nb", sub = {b = 2, a = 1}}
  print(s)
  ok(s, "go=nb seed=1\nsub\n  a=1 b=2") end

function halves(    tbl,tr,te) --> TAB; `the.file` as train and test TABs,
  tbl    = Tab(the.file)
  tr, te = tbl:split()
  tr, te = tbl:clone(tr), tbl:clone(te)
  return tr, te, function(row) return tr:ydist(row) end end

function slow.tree(    tr,te,y,i) --> nil
  tr, te, y = halves()
  i = Tree(tr, tr.rows, y)
  about()                     -- :config, then :tree -- two sections,
  print"\n:tree"              -- which `,/pretty` draws as a table
  print(logfmt(i:dict())) end

function slow.show(    tr,te,y) --> nil
  tr, te, y = halves()
  about()
  Tree(tr, tr.rows, y):show() end

function slow.all(    tr,te,y,i,lo,m1,m2,d,err,n) --> nil
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
          return adds(te.rows, Num(), function(row)
                   return abs(y(row) - fn(row)) end).mu end
  m1 = err(function(row) return i:pick(row).mu end)
  m2 = err(function() return i.mu end)
  print("tree", m1, "grand mean", m2, "depth", d)
  assert(m1 < m2, "tree lost to the grand mean")
  n = argmin()                              -- what every cut runs on
  for _, v in ipairs{3, 9, 1, 5} do n(v, "row" .. v) end
  assert(n() == "row1" and select(2, n()) == 1)
  assert(argmin()() == nil)                 -- offered nothing, holds
  print"PASS tree" end

-- ---- start ------------------------------------------------------
for k, v in help:gmatch"\n%s+(%a+)=(%S+)" do the[k] = values(v)[1] end
the.file = the.train     -- tab-eg names its data file=; same default

if (arg and arg[0] or ""):find"tab%.lua$" then
  if #arg == 0 then eg["-h"]() else cli() end end

return _ENV
