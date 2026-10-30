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
  bins=7           numeric columns get this many bins
  budget=50        labels, all in
  check=5          of those, saved for the test rows
  decs=2           decimals, when a number is printed
  m=2              m-estimate: prior weight for a thin bin
  p=2              minkowski coefficient
  seed=1234567891  random number seed
  file=~/gits/moot/optimize/misc/auto93.csv

actions:
   -h              print help
   --secs          time rmeans: train, then guess
   --all           unit tests (--num, --split ... run just one)]]

floor, exp, sqrt, log = math.floor, math.exp, math.sqrt, math.log
abs, min, max = math.abs, math.min, math.max

TAB,NUM,SYM,BINS,RMEANS,NB,BAG,SAME,BEST = {},{},{},{},{},{},{},{},{}

-- ---- misc ---------------------------------------------------------
-- Connect the instance `i` to its class `meta`.  `it` names that
-- class, so `col.it == SYM` asks what `getmetatable(col) == SYM`
-- asked.  It is set on the class, not the instance, so it costs one
-- field for all of them and `copy`'s `pairs` never finds it -- which
-- matters, since copying it would deep copy the class itself.
function new(meta,i) --> inst
  meta.__index, meta.it = meta, meta
  return setmetatable(i, meta) end

-- Update `the` from the command line: a flag, an action, or a file.
function cli(k,v) --> dict
  for _, s in order(arg) do        -- name=value, action, file
    k, v = s:match"^(%a%w*)=(.*)$"
    if     k     then the[k] = thing(v)
    elseif eg[s] then eg[s]()
    else              the.file = s end end
  return the end

-- Return an int in 1..`n`, repeatable from `the.seed`.
function rint(n) --> int
  the.seed = (16807 * the.seed) % 2147483647
  return 1 + floor(n * the.seed / 2147483647) end

-- Return `t`, Fisher-Yates shuffled in place.
function shuffle(t,    j) --> list
  for k = #t, 2, -1 do j = rint(k); t[k], t[j] = t[j], t[k] end
  return t end

-- Return `fn(v,k)` over `t`, in order, with nils dropped.
function map(t,fn,    u) --> list
  u={}; for k, v in ipairs(t) do u[#u+1] = fn(v, k) end 
  return u end                                        

-- Return `fn(v,k)` over every item of `t`, added up.
function sum(t,fn,    n) --> num
  n=0; for k, v in pairs(t) do n = n + fn(v, k) end; return n end

-- Return the key of `t` with the biggest `fn(v,k)`, and that score.
function best(t,fn,    n,m,u) --> any
  for k, v in pairs(t) do
    m = fn(v, k)
    if not n or m > n then n, u = m, k end end
  return u, n end

-- Return a BEST: the best thing shown to it so far, in `has`, and
-- that thing's score, in `score`.  `cmp` says what best means, so
-- `lt` keeps the smallest.  Where `best` wants a whole collection in
-- hand, this takes a scan one item at a time, and so can ride along
-- with a scan that is running anyway.
function Best(cmp) --> BEST
  return new(BEST, {cmp = cmp}) end

-- Show `i` a `payload` scoring `score`; return what `i` holds now.
-- Here is the best so far, here is one more thing: one compare, then
-- maybe a swap.  Nothing rejected is kept, so nothing is scanned twice.
function BEST.add(i,score,payload) --> any
  if i.score == nil or i.cmp(score, i.score) then
    i.score, i.has = score, payload end
  return i.has end

-- Return `x`.
function same(x) return x end --> any

-- Return true when `a` sorts before `b`.
function lt(a,b) return a < b end --> bool

-- Return `ipairs(t)`, or, given `fn`, that of a sorted copy.  `fn`
-- is a comparator, or a cell index to sort rows on.
function order(t,fn,    u,at) --> fun
  if not fn then return ipairs(t) end -- copy's ipairs. fn: a comparator,
  if type(fn) ~= "function" then     -- or a cell index to sort rows on
    at = fn; fn = function(a,b) return a[at] < b[at] end end
  u = map(t, same); table.sort(u, fn); return ipairs(u) end

-- Return `x:atom` as text, with nums cut to `the.decs` decimals.
-- Whole numbers stay whole, so a count of 318 is not "318.00".
function str(x) --> str
  return type(x) == "number" and x ~= floor(x)
         and ("%." .. the.decs .. "f"):format(x) or tostring(x) end

-- Print the lot, tab separated, every number through `str`.  This
-- shadows lua's own print for everything sharing this `_ENV`, so
-- `decs=4` widens every number anything here ever prints.
function print(...) --> nil
  local out = {}
  for j = 1, select("#", ...) do out[j] = str((select(j, ...))) end
  io.write(table.concat(out, "\t"), "\n") end

-- Return the `str | num` in  `s:str`.
function thing(s) --> atom
  s = s:match"^%s*(.-)%s*$"; return tonumber(s) or s end

-- Return the `row`  in a  comma seperated `s:str`.
function cells(s) --> row
  local row = {}
  for v in (s .. ","):gmatch"(.-)," do row[#row + 1] = thing(v) end
  return row end

-- Return the `rows` in a  `file:str`.
function csv(file,    rows,s) --> rows
  rows = {}
  for line in io.lines((file:gsub("^~", os.getenv"HOME" or "~"))) do
    s = line:match"^%s*(.-)%s*$"
    if s ~= "" and s:sub(1, 1) ~= "#" then
      rows[#rows + 1] = cells(s) end end
  return rows end

-- ---- stats -----------------------------------------------------------
-- Return two samples, `xs` and `ys`, sorted, ready to compare.
function Same(xs,ys,    fn) --> SAME
  fn = function(t,    u)     u=map(t, same); table.sort(u); return u end 
  return new(SAME, {xs = fn(xs), ys = fn(ys)}) end

-- Return true when all three tests call `i.xs` and `i.ys` the same.
function SAME.ok(i) --> bool
  return i:cohen() <= .35 and i:cliffs() <= .195 and i:ks() <= 1.36 end

-- Return the gap between the two means, in pooled sds.
function SAME.cohen(i,    a,b,sd) --> num
  a, b = nums(i.xs, same), nums(i.ys, same)
  sd = sqrt(((a.n-1) * a:div()^2 + (b.n-1) * b:div()^2) / (a.n+b.n-2))
  return abs(a.mu - b.mu) / (sd + 1e-32) end

-- Return how often `i.xs` out-ranks `i.ys`, 0..1.
function SAME.cliffs(i,    xs,ys,gt,lt,j,k) --> num
  xs, ys, gt, lt, j, k = i.xs, i.ys, 0, 0, 0, 0
  for _, x in order(xs) do
    while j < #ys and ys[j+1] <  x do j = j + 1; k = j end
    while k < #ys and ys[k+1] == x do k = k + 1 end
    gt, lt = gt + j, lt + #ys - k end
  return abs(gt - lt) / (#xs * #ys) end

-- Return the widest gap of the two cdfs, in critical units.
function SAME.ks(i,    xs,ys,p,q,d,v) --> num
  xs, ys, p, q, d = i.xs, i.ys, 0, 0, 0
  while p < #xs and q < #ys do
    v = min(xs[p+1], ys[q+1])
    while p < #xs and xs[p+1] == v do p = p + 1 end
    while q < #ys and ys[q+1] == v do q = q + 1 end
    d = max(d, abs(p/#xs - q/#ys)) end
  return d / sqrt((#xs + #ys) / (#xs * #ys)) end

-- ---- columns ---------------------------------------------------------
-- NUM and SYM share one protocol: add, div, norm, bin.  Each verb's
-- two faces sit together below.  nVals is SYM's alone.

-- Return a NUM for `txt:str` at `at:num`: A-Z num, !+- goal, X skip.
function Num(txt,at) --> NUM
  txt, at = txt or "N", at or 0    -- no args: an anonymous num
  return new(NUM, {txt = txt, at = at, n = 0, mu = 0, m2 = 0,
                   w = txt:find"%-$" and 0 or 1}) end

-- Return a SYM for `txt:str` at `at:num`: a-z names, just counted.
function Sym(txt,at) --> SYM
  txt, at = txt or "S", at or 0
  return new(SYM, {txt = txt, at = at, n = 0, has = {},
                   w = txt:find"%-$" and 0 or 1}) end

-- Return one NUM summarizing `fn(x)` over `lst:list`.
function nums(lst,fn,    i) --> NUM
  i=Num(); for _,x in order(lst) do i:add(fn(x)) end; return i end

-- Add `v:atom` to `i`, keeping Welford's running mean and sd.  `inc`
-- of -1 takes `v` back out: the same three lines with their signs
-- flipped.  That is what lets one left-to-right scan move a row from
-- the right of a cut to its left without recounting either side.
function NUM.add(i,v,inc,    d) --> nil
  if v == "?" then return end
  inc = inc or 1
  i.n = i.n + inc
  if i.n <= 0 then i.n, i.mu, i.m2 = 0, 0, 0; return end
  d    = v - i.mu
  i.mu = i.mu + inc * d / i.n
  i.m2 = i.m2 + inc * d * (v - i.mu) end

-- Add one more `v:atom` to `i`'s counts.  `inc` of -1 takes one away,
-- and a count falling to zero leaves `has` outright: `div` sums over
-- those keys, and log(0) is nothing to add up.
function SYM.add(i,v,inc) --> nil
  if v == "?" then return end
  inc = inc or 1
  i.n = i.n + inc
  i.has[v] = (i.has[v] or 0) + inc
  if i.has[v] <= 0 then i.has[v] = nil end end

-- Return what is left of `i` once `j` is taken out of it: the other
-- side of a cut, in closed form.  Pooling says `i.m2` is its parts'
-- m2 plus n1*n2/n times their gap squared, so read that backwards.
function NUM.__sub(i,j,    n,d) --> NUM
  n = i.n - j.n
  if n < 1 then return Num(i.txt, i.at) end
  d = j.mu - i.mu
  return new(NUM, {txt = i.txt, at = i.at, w = i.w, n = n,
                   mu = (i.n*i.mu - j.n*j.mu) / n,
                   m2 = max(0, i.m2 - j.m2 - d*d*i.n*j.n/n)}) end

-- Return `i`'s standard deviation.
function NUM.div(i) --> num
  return i.n < 2 and 0 or sqrt(max(i.m2, 0) / (i.n - 1)) end

-- Return `i`'s entropy.
function SYM.div(i,    fn) --> num
  fn = function(n) return -n/i.n * log(n/i.n) end
  return sum(i.has, fn) / log(2) end

-- Return `v:atom` on a logistic cdf, clipped at 3 sds, so 0..1.
function NUM.norm(i,v,    z) --> atom
  if v == "?" then return v end
  z = (v - i.mu) / (i:div() + 1e-32)
  z = z > 3 and 3 or (z < -3 and -3 or z)
  return 1 / (1 + exp(-1.7 * z)) end

-- Return `v:atom` unchanged: syms do not normalize.
function SYM.norm(i,v) return v end --> atom

-- Return true when cell `x` is on `v`'s side of a cut.  An unknown
-- says yes to everything, so a cut never loses a row.
function SYM.holds(i,x,v) return x == "?" or x == v end --> bool
function NUM.holds(i,x,v) return x == "?" or x <= v end --> bool

-- Return `v:atom`'s bin, 1..`the.bins`.
function NUM.bin(i,v,    b) --> atom
  if v == "?" then return v end
  b = 1 + floor(the.bins * i:norm(v))
  return b > the.bins and the.bins or b end

-- Return `v:atom`: a sym is its own bin.
function SYM.bin(i,v) return v end --> atom

-- Return how many values `i` has seen, at least 2.
function SYM.nVals(i,    fn) --> int
  fn = function() return 1 end       -- one value still splits two ways
  i.kinds = i.kinds or max(2, sum(i.has, fn))
  return i.kinds end

-- ---- tables ----------------------------------------------------------
-- Return a TAB from `src`: a file name, or names then rows.
function Tab(src,    i) --> TAB
  i = new(TAB, {rows = {}})
  for _, row in order(type(src) == "string" and csv(src) or src) do
    i:addRow(row) end
  return i end

-- Read `names:row` as `i`'s column header.
function TAB.head(i,names,    col) --> nil
  i.names, i.cols, i.x, i.y = names, {}, {}, {}
  for at, txt in order(names) do
    col = (txt:find"^%u" and Num or Sym)(txt, at)
    i.cols[#i.cols + 1] = col
    if     txt:find"X$"     then                 -- summarized, skipped
    elseif txt:find"[-+!]$" then i.y[#i.y + 1] = col
      if txt:find"!$" then i.klass = col end  -- last ! is the klass
    else i.x[#i.x + 1] = col end end end

-- Add `row` to `i`.  The first row read becomes the names.
function TAB.addRow(i,row) --> row
  if not i.cols then return i:head(row) end
  i.rows[#i.rows + 1] = row
  for _, col in order(i.cols) do col:add(row[col.at]) end
  return row end

-- Return `rows` in a fresh TAB; `how:str`="bin" discretizes the nums.
function TAB.clone(i,rows,how,    out) --> TAB
  out = {how and map(i.cols, function(col) return col.txt:lower() end)
             or i.names}
  for _, row in order(rows or {}) do
    out[#out + 1] = not how and row or map(i.cols,
      function(col) return col[how](col, row[col.at]) end) end
  return Tab(out) end

-- Return `row`'s distance to heaven over `i.y`, where 0 is best.
function TAB.ydist(i,row,    fn) --> num
  fn = function(col)
          return abs(col:norm(row[col.at]) - col.w) ^ the.p end
  return (sum(i.y, fn) / #i.y) ^ (1 / the.p) end

-- Return two lists, 80:20, of a shuffled copy of `i.rows`.
function TAB.split(i,    rows,n,t,u1,u2) --> list
  rows   = shuffle(map(i.rows, same))    -- never i.rows itself
  n      = floor(.8 * #rows)
  u1, u2 = {}, {}; t = u1
  for j,row in order(rows) do if j>n then t = u2 end; t[#t+1] = row end
  return u1, u2 end

-- ---- rmeans ----------------------------------------------------------
-- Return `col`'s bins over `rows`, scored on `y`, and their worth.
function Bins(col,rows,y,all,    i,b) --> BINS
  i = new(BINS, {has = {}, w = 0})
  for _, row in order(rows) do
    b = col:bin(row[col.at])
    i.has[b] = i.has[b] or Num()
    i.has[b]:add(y(row)) end
  i.w = i:weight(all)
  return i end

-- Return how much of `all:NUM`'s variance `i`'s bins cut off.
function BINS.weight(i,all,    fn,s) --> num
  fn = function(v) return v.n/all.n * v:div() ^ 2 end
  s = all:div() ^ 2 - sum(i.has, fn)
  return s > 0 and s or 0 end

-- Return one BINS per x column of `tbl:TAB`, over `rows`, on `y`.
function Rmeans(tbl,rows,y,    sub,all,i) --> RMEANS
  sub = tbl:clone(rows)
  all = nums(sub.rows, y)
  i   = new(RMEANS, {all = all, has = {}, cols = sub.x})
  for _, col in order(sub.x) do
    i.has[col.at] = Bins(col, sub.rows, y, all) end
  return i end

-- Return `row`'s guess: bin means, m-estimated, weighed by variance.
function RMEANS.guess(i,row,    s,w,bins,v,mu) --> num
  s, w, mu = 0, 0, i.all.mu
  for _, col in order(i.cols) do
    bins = i.has[col.at]
    v    = bins and bins.has[col:bin(row[col.at])]
    if v and bins.w > 0 then
      s = s + bins.w * (v.n * v.mu + the.m * mu) / (v.n + the.m)
      w = w + bins.w end end
  if w > 0 then return s / w end
  return i.all.mu end

-- Return `i` with only the columns worth their weight: "max" or
-- "chance".
function RMEANS.prune(i,how,    fn,_,most) --> RMEANS
  fn = function(col) return i.has[col.at].w end
  _, most = best(i.cols, fn)
  i.cols = map(i.cols, function(col)
    return (how == "max" and fn(col) >= .1 * most
            or how == "chance" and fn(col) > i:chance(i.has[col.at]))
           and col or nil end)
  return i end

-- Return the variance `b`'s random bins would cut from `i.all`.
function RMEANS.chance(i,b,    fn,k) --> num
  fn = function() return 1 end
  k   = sum(b.has, fn)
  return (k - 1) / max(1, i.all.n - 1) * i.all:div() ^ 2 end

-- ---- bayes -----------------------------------------------------------
-- Return one sub-TAB per klass in `rows`, and how many klasses.
function Nb(tbl,rows,    i,col,v) --> NB
  col = tbl.klass
  i   = new(NB, {tbl = tbl, subs = {}, n = #rows, nKlass = 0})
  for _, row in order(rows) do
    v = row[col.at]
    if not i.subs[v] then
      i.subs[v], i.nKlass = tbl:clone(), i.nKlass + 1 end
    i.subs[v]:addRow(row) end
  return i end

-- Return log P(`row` | `sub:TAB`), m-estimated.
function NB.like(i,sub,row,    fn) --> num
  fn = function(col1,at,    col,v)
        col, v = i.tbl.x[at], row[col1.at] -- col knows every value;
        if v == "?" then return 0 end      -- col1 knows this klass's
        return log(((col1.has[v] or 0) + the.m)    -- and m per value
                   / (col1.n + the.m * col:nVals())) end
  return log((#sub.rows + the.m) / (i.n + the.m * i.nKlass)) -- m/klass
         + sum(sub.x, fn) end

-- Return `row`'s likeliest klass.
function NB.guess(i,row,    fn) --> atom
  fn = function(sub) return i:like(sub, row) end
  return (best(i.subs, fn)) end

-- ---- scoring ---------------------------------------------------------
-- Return blank counts, for one test set.
function Bag() --> BAG
  return new(BAG, {n = 0, ok = 0, got = {}, want = {}, hit = {}}) end

-- Add one guess to `i`: `want:atom` was right, `got:atom` was said.
function BAG.tally(i,want,got) --> nil
  i.n          = i.n + 1
  i.ok         = i.ok + (want == got and 1 or 0)
  i.want[want] = (i.want[want] or 0) + 1
  i.got[got]   = (i.got[got] or 0) + 1
  if want == got then i.hit[got] = (i.hit[got] or 0) + 1 end end

-- Return klass `x:atom`'s tp, fp, fn and tn, counted so far.
function BAG.parts(i,x,    tp,fp,fn) --> int
  tp = i.hit[x] or 0
  fp = (i.got[x] or 0) - tp
  fn = (i.want[x] or 0) - tp
  return tp, fp, fn, i.n - fn - fp - tp end

-- Return klass `x:atom`'s pd, pf and d2h.
function BAG.score1(i,x,    tp,fp,fn,tn,r1,f1) --> num
  tp, fp, fn, tn = i:parts(x)
  r1 = tp / (tp + fn)
  f1 = fp + tn > 0 and fp / (fp + tn) or 0
  return r1, f1, sqrt((1 - r1) ^ 2 + f1 ^ 2) / sqrt(2) end

-- Return `i`'s macro acc, pd, pf, d2h and klass count.
function BAG.score(i,    k,pd,pf,d2h,r1,f1,d1) --> num
  k, pd, pf, d2h = 0, 0, 0, 0
  for x in pairs(i.want) do
    r1, f1, d1 = i:score1(x)
    k, pd, pf, d2h = k + 1, pd + r1, pf + f1, d2h + d1 end
  return 100*i.ok/i.n, 100*pd/k, 100*pf/k, d2h/k, k end

-- ---- tests ------------------------------------------------------
eg  = {}                           -- cli runs eg[action]; see --all
-- Return true when `a:num` and `b:num` are close enough.
function near(a,b) return abs(a - b) < 1e-6 end --> bool

eg["-h"] = function() print(help) end

eg["--all"] = function(    b4,keys) -- every test action, a-z order,
  b4, keys = the.seed, {}           -- each from a fresh seed
  for key in pairs(eg) do           -- skip the non-test actions:
    if not (" -h --secs --all "):find(" "..key.." ", 1, true) then
      keys[#keys + 1] = key end end
  for _, key in order(keys, lt) do the.seed = b4; eg[key]() end
  print("PASS " .. #keys .. " tests") end

eg["--secs"] = function(  file,tbl,reps,tot,t0,tr,te,sub,y,model,lim,
                          seed)
  file = the.file                   -- time rmeans: train, then guess
  tbl, reps, tot, seed = Tab(file), 3, 0, the.seed
  for s = 1, reps do
    the.seed = seed + s
    tr, te = tbl:split()
    sub = tbl:clone(tr)
    y   = function(row) return sub:ydist(row) end
    lim = the.budget - the.check
    t0  = os.clock()
    do
      local few = {}
      for j = 1, (#tr < lim and #tr or lim) do few[j] = tr[j] end
      model = Rmeans(tbl, few, y)
      for _, row in order(te) do model:guess(row) end
    end
    tot = tot + (os.clock() - t0) end
  print(string.format("%s rows=%6d secs=%.4f",
                      file:match"([^/]+)%.csv$", #tbl.rows,
                      tot / reps)) end

eg["--thing"] = function()
  print("thing", thing" 42 ", thing"x", thing"4.2")
  assert(thing" 42 " == 42 and thing"x" == "x" and thing"4.2" == 4.2)
  assert(thing"  a b " == "a b") end

eg["--cells"] = function(    t)
  t = cells"1, a,2.5,?"
  print("cells", table.concat(t, "|"))
  assert(#t == 4 and t[1] == 1 and t[2] == "a" and t[3] == 2.5)
  assert(t[4] == "?") end

eg["--csv"] = function(    t)
  t = csv(the.file)
  print("csv", #t, #t[1], t[1][1])
  assert(#t == 399 and #t[1] == 8)
  assert(t[1][1] == "Clndrs" and t[2][1] == 8) end

eg["--map"] = function(    t)
  t = map({10,20,30}, function(v,k) return v + k end)
  print("map", table.concat(t, ","))
  assert(t[1] == 11 and t[2] == 22 and t[3] == 33)
  t = map({1,2,3,4}, function(v) return v % 2 == 0 and v or nil end)
  assert(#t == 2 and t[1] == 2 and t[2] == 4) end -- nils drop

eg["--sum"] = function(    n)
  n = sum({1,2,3}, same)
  print("sum", n, sum({a=1,b=2}, same))
  assert(n == 6 and sum({a=1,b=2}, same) == 3)
  assert(sum({4,5}, function(v,k) return k end) == 3) end

eg["--best"] = function(    k,n)
  k, n = best({3,9,5}, same)
  print("best", k, n)
  assert(k == 2 and n == 9)
  k = best({x=1,y=9}, same)
  assert(k == "y") end

eg["--rint"] = function(    a,b,c,d)
  the.seed = 1234567891
  a, b, c, d = rint(100), rint(100), rint(100), rint(100)
  print("rint", a, b, c, d)
  assert(a == 19 and b == 70 and c == 6 and d == 8) end

eg["--shuffle"] = function(    t)
  the.seed = 1234567891
  t = shuffle{1,2,3,4,5,6,7,8,9,10}
  print("shuffle", table.concat(t, ","))
  assert(table.concat(t, ",") == "10,9,4,3,6,5,8,1,7,2") end

eg["--num"] = function(    i)
  i = Num(); for x = 1, 10 do i:add(x) end
  print("num", i.mu, i:div())
  assert(i.n == 10 and i.mu == 5.5 and near(i:div(), 3.0276503541))
  i:add"?"; assert(i.n == 10)                 -- "?" is a no-op
  assert(Num("Lbs-").w == 0 and Num("Acc+").w == 1) end

eg["--norm"] = function(    i)
  i = Num(); for x = 1, 10 do i:add(x) end
  print("norm", i:norm(8), i:norm(999))
  assert(near(i:norm(8),   0.8027749262))
  assert(near(i:norm(999), 0.9939401985))     -- clipped at 3 sds
  assert(i:norm"?" == "?") end

eg["--bin"] = function(    i)
  i = Num(); for x = 1, 10 do i:add(x) end
  print("bin", i:bin(8), i:bin(999), i:bin(-999))
  assert(i:bin(8) == 6 and i:bin(999) == the.bins and i:bin(-999) == 1)
  assert(i:bin"?" == "?") end

eg["--sym"] = function(    i)
  i = Sym(); for _, v in order{"a","a","b","c","c","c"} do i:add(v) end
  print("sym", i.n, i.has.c, i:div(), i:nVals())
  assert(i.n == 6 and i.has.c == 3 and i:nVals() == 3)
  assert(near(i:div(), 1.4591479170))
  assert(i:norm"c" == "c" and i:bin"c" == "c")  -- syms pass through
  assert(Sym():nVals() == 2) end             -- one value, two ways

eg["--nums"] = function(    i)
  i = nums({1,2,3,4}, same)
  print("nums", i.mu)
  assert(i.mu == 2.5 and i.n == 4) end

eg["--tbl"] = function(    t)
  t = Tab(the.file)
  print("tbl", #t.rows, #t.cols, #t.x, #t.y)
  assert(#t.rows == 398 and #t.cols == 8 and #t.x == 4 and #t.y == 3)
  assert(t.cols[6].w == 0 and t.klass == nil)  -- Lbs- runs to zero
  assert(near(t.cols[2].mu,    193.425879))
  assert(near(t.cols[2]:div(), 104.269838)) end

eg["--head"] = function(    t)
  t = Tab{ {"Age","HpX","speed-","klass!"} }
  print("head", #t.x, #t.y, t.klass.txt)
  assert(#t.x == 1 and #t.y == 2)              -- HpX summarized, skipped
  assert(t.klass.txt == "klass!" and t.cols[3].w == 0)
  assert(t.cols[1].it == NUM)              -- A-Z: num; a-z: sym
  assert(t.cols[4].it == SYM) end

eg["--clone"] = function(    t,u)
  t = Tab(the.file)
  u = t:clone(t.rows)
  print("clone", #u.rows, u.cols[2].mu)
  assert(#u.rows == #t.rows and near(u.cols[2].mu, t.cols[2].mu))
  u = t:clone({t.rows[1]}, "bin")              -- bin makes all syms
  assert(table.concat(u.rows[1], ",") == "7,7,7,1,1,7,7,1")
  assert(u.names[1] == "clndrs")
  assert(u.cols[2].it == SYM) end

eg["--ydist"] = function(    t,d)
  t = Tab(the.file)
  d = t:ydist(t.rows[1])
  print("ydist", d, t:ydist(t.rows[398]))
  assert(near(d, 0.7863215821))                -- a gas guzzler is far
  assert(near(t:ydist(t.rows[398]), 0.1410148526)) -- a honda is near
  assert(d >= 0 and d <= 1) end

eg["--split"] = function(    t,tr,te)
  the.seed = 1234567891
  t = Tab(the.file)
  tr, te = t:split()
  print("split", #tr, #te, table.concat(tr[1], ","))
  assert(#tr == 318 and #te == 80)
  assert(table.concat(tr[1], ",") == "6,145,76,81,2,3160,19.6,30")
  assert(table.concat(te[1], ",") == "4,97,75,75,3,2171,16,30")
  assert(t.rows[1][1] == 8) end               -- t.rows undisturbed

eg["--bins"] = function(    t,y,few,sub,b)
  t, few = Tab(the.file), {}
  y = function(row) return t:ydist(row) end
  for k = 1, 45 do few[k] = t.rows[k] end
  sub = t:clone(few)                -- bins come from the labeled few,
  b = Bins(sub.x[2], sub.rows, y, nums(sub.rows, y)) -- not the world
  print("bins", b.w)
  assert(near(b.w, 0.0013005425) and b.w >= 0) end

eg["--rmeans"] = function(    t,y,few,model)
  t, few = Tab(the.file), {}
  y = function(row) return t:ydist(row) end
  for k = 1, 45 do few[k] = t.rows[k] end
  model = Rmeans(t, few, y)
  print("rmeans", model.all.mu, model:guess(t.rows[1]))
  assert(near(model.all.mu,          0.9009519530))
  assert(near(model:guess(t.rows[1]),   0.8530303902))
  assert(near(model:guess(t.rows[200]), 0.8535267151)) end

eg["--prune"] = function(    t,y,few)
  t, few = Tab(the.file), {}
  y = function(row) return t:ydist(row) end
  for k = 1, 45 do few[k] = t.rows[k] end
  print("prune", #Rmeans(t,few,y):prune("max").cols,
                 #Rmeans(t,few,y):prune("chance").cols)
  assert(#Rmeans(t, few, y):prune("max").cols    == 2)
  assert(#Rmeans(t, few, y):prune("chance").cols == 2) end

eg["--chance"] = function(    t,y,few,model)
  t, few = Tab(the.file), {}
  y = function(row) return t:ydist(row) end
  for k = 1, 45 do few[k] = t.rows[k] end
  model = Rmeans(t, few, y)
  print("chance", model:chance(model.has[t.x[2].at]))
  assert(near(model:chance(model.has[t.x[2].at]), 0.0002607692)) end

eg["--nb"] = function(    t,b,i)
  t = Tab{ {"Age","job","klass!"},
           {20,"low","no"},  {22,"low","no"}, {25,"low","no"},
           {30,"med","no"},  {60,"hi","yes"}, {62,"hi","yes"},
           {65,"med","yes"}, {70,"hi","yes"} }
  b = t:clone(t.rows, "bin")
  i = Nb(b, b.rows)
  print("nb", i.nKlass, i:guess(b.rows[1]), i:guess(b.rows[8]))
  assert(i.nKlass == 2)
  assert(i:guess(b.rows[1]) == "no" and i:guess(b.rows[8]) == "yes")
  assert(near(i:like(i.subs.no,  b.rows[1]), -2.7725887222))
  assert(near(i:like(i.subs.yes, b.rows[1]), -4.0943445622)) end

eg["--bag"] = function(    i,tp,fp,fn,tn,acc,pd,pf,d2h,k)
  i = Bag()
  for _, t in order{ {"a","a"},{"a","b"},{"b","b"},{"b","b"},
                     {"b","a"} } do i:tally(t[1], t[2]) end
  tp, fp, fn, tn = i:parts"a"
  print("bag", tp, fp, fn, tn)
  assert(tp == 1 and fp == 1 and fn == 1 and tn == 2)
  pd, pf, d2h = i:score1"a"
  assert(near(pd, .5) and near(pf, 1/3) and near(d2h, 0.4249182928))
  acc, pd, pf, d2h, k = i:score()
  assert(near(acc, 60) and near(pd, 58.333333) and k == 2)
  assert(near(pf, 41.666667) and near(d2h, 0.424918)) end

eg["--same"] = function(    xs,ys,zs,i)
  xs, ys, zs = {}, {}, {}
  for k = 1, 20 do xs[k] = k; ys[k] = k + .5; zs[k] = k + 20 end
  i = Same(xs, ys)
  print("same", i:ok(), Same(xs, zs):ok())
  assert(i:ok() and not Same(xs, zs):ok())
  assert(near(i:cohen(),  0.0845154255))
  assert(near(i:cliffs(), 0.05))
  assert(near(i:ks(),     0.1581138830))
  assert(near(Same(xs, xs):cohen(), 0)) end

-- ---- start ------------------------------------------------------
for k, v in help:gmatch"\n%s+(%a+)=(%S+)" do the[k] = thing(v) end

if (arg and arg[0] or ""):find"tab%.lua$" then
  if #arg == 0 then eg["-h"]() else cli() end end

return _ENV
