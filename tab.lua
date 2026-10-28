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

TAB,NUM,SYM,BINS,RMEANS,NB,BAG,SAME = {},{},{},{},{},{},{},{}

-- ---- misc ---------------------------------------------------------
function new(meta,i)                -- Connect an instance to its class.
  meta.__index = meta; return setmetatable(i, meta) end

function cli(k,v) -- Update config X via cli X=Y. Also, execut --fun items.
  for _, s in order(arg) do        -- name=value, action, file
    k, v = s:match"^(%a%w*)=(.*)$"
    if     k     then the[k] = thing(v)
    elseif eg[s] then eg[s]()
    else              the.file = s end end
  return the end

function rint(n)                    -- 1..n, repeatable from the.seed
  the.seed = (16807 * the.seed) % 2147483647
  return 1 + floor(n * the.seed / 2147483647) end

function shuffle(t,    j)           -- in place, Fisher-Yates
  for k = #t, 2, -1 do j = rint(k); t[k], t[j] = t[j], t[k] end
  return t end

function map(t,f,    u)      -- f(v,k) over t,in order; nils are dropped
  u={}; for k, v in ipairs(t) do u[#u+1] = f(v, k) end 
  return u end                                        

function sum(t,f,    n)             -- f(v,k) over t's items, added up
  n=0; for k, v in pairs(t) do n = n + f(v, k) end; return n end

function best(t,f,    n,m,u)        -- the k, and biggest f(v,k), in t
  for k, v in pairs(t) do
    m = f(v, k)
    if not n or m > n then n, u = m, k end end
  return u, n end

function same(x) return x end       -- identity

function lt(a,b) return a < b end   -- ascending, for order

function order(t,f,    u,at)        -- ipairs; or, given f, a sorted
  if not f then return ipairs(t) end -- copy's ipairs. f: a comparator,
  if type(f) ~= "function" then     -- or a cell index to sort rows on
    at = f; f = function(a,b) return a[at] < b[at] end end
  u = map(t, same); table.sort(u, f); return ipairs(u) end

function thing(s)                   -- one cell: number, or the string
  s = s:match"^%s*(.-)%s*$"; return tonumber(s) or s end

function cells(s,    row) row = {}
  for v in (s .. ","):gmatch"(.-)," do row[#row + 1] = thing(v) end
  return row end

function csv(file,    rows,s) rows = {} -- first row is the names
  for line in io.lines((file:gsub("^~", os.getenv"HOME" or "~"))) do
    s = line:match"^%s*(.-)%s*$"
    if s ~= "" and s:sub(1, 1) ~= "#" then
      rows[#rows + 1] = cells(s) end end
  return rows end

-- ---- stats -----------------------------------------------------------
function Same(xs,ys,    f)  -- two samples, sorted, to compare
  f = function(t,    u)     u=map(t, same); table.sort(u); return u end 
  return new(SAME, {xs = f(xs), ys = f(ys)}) end

function SAME.ok(i)                 -- do all three tests say "same"?
  return i:cohen() <= .35 and i:cliffs() <= .195 and i:ks() <= 1.36 end

function SAME.cohen(i,    a,b,sd)   -- gap of means, in pooled sds
  a, b = nums(i.xs, same), nums(i.ys, same)
  sd = sqrt(((a.n-1) * a:div()^2 + (b.n-1) * b:div()^2) / (a.n+b.n-2))
  return abs(a.mu - b.mu) / (sd + 1e-32) end

function SAME.cliffs(i,    xs,ys,gt,lt,j,k) -- how often xs out-ranks ys
  xs, ys, gt, lt, j, k = i.xs, i.ys, 0, 0, 0, 0
  for _, x in order(xs) do
    while j < #ys and ys[j+1] <  x do j = j + 1; k = j end
    while k < #ys and ys[k+1] == x do k = k + 1 end
    gt, lt = gt + j, lt + #ys - k end
  return abs(gt - lt) / (#xs * #ys) end

function SAME.ks(i,    xs,ys,p,q,d,v) -- widest gap of two cdfs, in crits
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

function Num(txt,at)                -- ! + -: goals.  X: skip.  A-Z: num
  txt, at = txt or "N", at or 0    -- no args: an anonymous num
  return new(NUM, {txt = txt, at = at, n = 0, mu = 0, m2 = 0,
                   w = txt:find"%-$" and 0 or 1}) end

function Sym(txt,at)                -- a-z names; counts, not Welford
  txt, at = txt or "S", at or 0
  return new(SYM, {txt = txt, at = at, n = 0, has = {},
                   w = txt:find"%-$" and 0 or 1}) end

function nums(lst,f,    i)          -- lst, summarized in one num
  i=Num(); for _,x in order(lst) do i:add(f(x)) end; return i end

function NUM.add(i,v,    d)         -- Welford's running mean and sd
  if v == "?" then return end
  i.n = i.n + 1
  d = v - i.mu
  i.mu = i.mu + d / i.n
  i.m2 = i.m2 + d * (v - i.mu) end

function SYM.add(i,v)               -- one more of v
  if v == "?" then return end
  i.n = i.n + 1
  i.has[v] = (i.has[v] or 0) + 1 end

function NUM.div(i)                 -- standard deviation
  return i.n < 2 and 0 or sqrt(i.m2 / (i.n - 1)) end

function SYM.div(i,    f)           -- entropy
  f = function(n) return -n/i.n * log(n/i.n) end
  return sum(i.has, f) / log(2) end

function NUM.norm(i,v,    z)        -- logistic cdf, clipped at 3 sds
  if v == "?" then return v end
  z = (v - i.mu) / (i:div() + 1e-32)
  z = z > 3 and 3 or (z < -3 and -3 or z)
  return 1 / (1 + exp(-1.7 * z)) end

function SYM.norm(i,v) return v end -- syms pass through

function NUM.bin(i,v,    b)         -- 1..the.bins
  if v == "?" then return v end
  b = 1 + floor(the.bins * i:norm(v))
  return b > the.bins and the.bins or b end

function SYM.bin(i,v) return v end  -- a sym is its own bin

function SYM.nVals(i,    f)         -- how many values i has seen;
  f = function() return 1 end       -- one value still splits two ways
  i.kinds = i.kinds or max(2, sum(i.has, f))
  return i.kinds end

-- ---- tables ----------------------------------------------------------
function Tab(src,    i)             -- a file name, or names then rows
  i = new(TAB, {rows = {}})
  for _, row in order(type(src) == "string" and csv(src) or src) do
    i:addRow(row) end
  return i end

function TAB.head(i,names,    col)  -- the first row, read as names
  i.names, i.cols, i.x, i.y = names, {}, {}, {}
  for at, txt in order(names) do
    col = (txt:find"^%u" and Num or Sym)(txt, at)
    i.cols[#i.cols + 1] = col
    if     txt:find"X$"     then                 -- summarized, skipped
    elseif txt:find"[-+!]$" then i.y[#i.y + 1] = col
      if txt:find"!$" then i.klass = col end  -- last ! is the klass
    else                         i.x[#i.x + 1] = col end end end

function TAB.addRow(i,row)          -- first row is the names
  if not i.cols then return i:head(row) end
  i.rows[#i.rows + 1] = row
  for _, col in order(i.cols) do col:add(row[col.at]) end
  return row end

function TAB.clone(i,rows,how,    out) -- same header, fresh summaries
  out = {how and map(i.cols, function(col) return col.txt:lower() end)
             or i.names}         -- how makes nums discrete, so sym
  for _, row in order(rows or {}) do
    out[#out + 1] = not how and row or map(i.cols,
      function(col) return col[how](col, row[col.at]) end) end
  return Tab(out) end

function TAB.ydist(i,row,    f)   -- goals to heaven; 0 is best
  f = function(col)
          return abs(col:norm(row[col.at]) - col.w) ^ the.p end
  return (sum(i.y, f) / #i.y) ^ (1 / the.p) end

function TAB.split(i,    rows,n,t,u1,u2) -- never shuffles i.rows
  rows   = shuffle(map(i.rows, same))    -- itself
  n      = floor(.8 * #rows)
  u1, u2 = {}, {}; t = u1
  for j,row in order(rows) do if j>n then t = u2 end; t[#t+1] = row end
  return u1, u2 end

-- ---- rmeans ----------------------------------------------------------
function Bins(col,rows,y,all,    i,b) -- col's bins, and their worth
  i = new(BINS, {has = {}, w = 0})
  for _, row in order(rows) do
    b = col:bin(row[col.at])
    i.has[b] = i.has[b] or Num()
    i.has[b]:add(y(row)) end
  i.w = i:weight(all)
  return i end

function BINS.weight(i,all,    f,s) -- variance i's bins cut off
  f = function(v) return v.n/all.n * v:div() ^ 2 end
  s = all:div() ^ 2 - sum(i.has, f)
  return s > 0 and s or 0 end

function Rmeans(tbl,rows,y,    sub,all,i) -- one bins per x column
  sub = tbl:clone(rows)
  all = nums(sub.rows, y)
  i   = new(RMEANS, {all = all, has = {}, cols = sub.x})
  for _, col in order(sub.x) do
    i.has[col.at] = Bins(col, sub.rows, y, all) end
  return i end

function RMEANS.guess(i,row,    s,w,bins,v,mu) -- bin means, m-estimated,
  s, w, mu = 0, 0, i.all.mu               -- weighed by variance won
  for _, col in order(i.cols) do
    bins = i.has[col.at]
    v    = bins and bins.has[col:bin(row[col.at])]
    if v and bins.w > 0 then
      s = s + bins.w * (v.n * v.mu + the.m * mu) / (v.n + the.m)
      w = w + bins.w end end
  if w > 0 then return s / w end
  return i.all.mu end

function RMEANS.prune(i,how,    f,_,most) -- after training, keep only
  f = function(col) return i.has[col.at].w end -- cols worth their
  _, most = best(i.cols, f)           -- weight: "max", >= 10% of the
  i.cols = map(i.cols, function(col)  -- best; "chance", more than
    return (how == "max" and f(col) >= .1 * most  -- noise would cut
            or how == "chance" and f(col) > i:chance(i.has[col.at]))
           and col or nil end)
  return i end

function RMEANS.chance(i,b,    f,k) -- variance k random bins would cut
  f = function() return 1 end       -- from all: (k-1)/(n-1) of it
  k = sum(b.has, f)
  return (k - 1) / max(1, i.all.n - 1) * i.all:div() ^ 2 end

-- ---- bayes -----------------------------------------------------------
function Nb(tbl,rows,    i,col,v)   -- one sub-table per klass, and
  col = tbl.klass                   -- how many klasses that turned
  i   = new(NB, {tbl = tbl, subs = {}, n = #rows, nKlass = 0})
  for _, row in order(rows) do
    v = row[col.at]
    if not i.subs[v] then
      i.subs[v], i.nKlass = tbl:clone(), i.nKlass + 1 end
    i.subs[v]:addRow(row) end
  return i end

function NB.like(i,sub,row,    f) -- log P(row|sub), m-estimated
  f = function(col1,at,    col,v)
        col, v = i.tbl.x[at], row[col1.at] -- col knows every value;
        if v == "?" then return 0 end      -- col1 knows this klass's
        return log(((col1.has[v] or 0) + the.m)    -- and m per value
                   / (col1.n + the.m * col:nVals())) end
  return log((#sub.rows + the.m) / (i.n + the.m * i.nKlass)) -- m/klass
         + sum(sub.x, f) end

function NB.guess(i,row,    f)      -- row's likeliest klass
  f = function(sub) return i:like(sub, row) end
  return (best(i.subs, f)) end

-- ---- scoring ---------------------------------------------------------
function Bag()                      -- blank counts, for one test set
  return new(BAG, {n = 0, ok = 0, got = {}, want = {}, hit = {}}) end

function BAG.tally(i,want,got)      -- one guess, into the bag
  i.n          = i.n + 1
  i.ok         = i.ok + (want == got and 1 or 0)
  i.want[want] = (i.want[want] or 0) + 1
  i.got[got]   = (i.got[got] or 0) + 1
  if want == got then i.hit[got] = (i.hit[got] or 0) + 1 end end

function BAG.parts(i,x,    tp,fp,fn) -- x's tp, fp, fn, tn, so far
  tp = i.hit[x] or 0
  fp = (i.got[x] or 0) - tp
  fn = (i.want[x] or 0) - tp
  return tp, fp, fn, i.n - fn - fp - tp end

function BAG.score1(i,x,    tp,fp,fn,tn,r1,f1) -- x's pd, pf, and d2h
  tp, fp, fn, tn = i:parts(x)
  r1 = tp / (tp + fn)
  f1 = fp + tn > 0 and fp / (fp + tn) or 0
  return r1, f1, sqrt((1 - r1) ^ 2 + f1 ^ 2) / sqrt(2) end

function BAG.score(i,    k,pd,pf,d2h,r1,f1,d1) -- macro: one vote each
  k, pd, pf, d2h = 0, 0, 0, 0
  for x in pairs(i.want) do
    r1, f1, d1 = i:score1(x)
    k, pd, pf, d2h = k + 1, pd + r1, pf + f1, d2h + d1 end
  return 100*i.ok/i.n, 100*pd/k, 100*pf/k, d2h/k, k end

-- ---- tests ------------------------------------------------------
eg  = {}                           -- cli runs eg[action]; see --all
function near(a,b) return abs(a - b) < 1e-6 end

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
  assert(getmetatable(t.cols[1]) == NUM)       -- A-Z: num; a-z: sym
  assert(getmetatable(t.cols[4]) == SYM) end

eg["--clone"] = function(    t,u)
  t = Tab(the.file)
  u = t:clone(t.rows)
  print("clone", #u.rows, u.cols[2].mu)
  assert(#u.rows == #t.rows and near(u.cols[2].mu, t.cols[2].mu))
  u = t:clone({t.rows[1]}, "bin")              -- bin makes all syms
  assert(table.concat(u.rows[1], ",") == "7,7,7,1,1,7,7,1")
  assert(u.names[1] == "clndrs")
  assert(getmetatable(u.cols[2]) == SYM) end

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
