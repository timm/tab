#!/usr/bin/env lua
-- vim: set ts=2 sw=2 sts=2 et cc=75 :
-- tab-eg.lua: the rigs.  A split is a seed, not a file: `rint` is
-- Park-Miller and stays under 2^53, so lua, python and lisp all
-- shuffle a table into the same order.  Only scores reach the disk.
-- Everything here is idempotent: work already cached is never
-- redone (pass force=y to insist).
-- usage: luajit tab-eg.lua go=nb     file=f.csv
--        luajit tab-eg.lua go=rmeans file=f.csv
--        luajit tab-eg.lua go=splits file=f.csv  (what seed s gives)
package.path = (arg[0]:match"^(.*)/" or ".") .. "/?.lua;" .. package.path
local tab = require "tab"
if setfenv then setfenv(1, tab) end          -- tab's _ENV is ours too
local _ENV = tab
cache = os.getenv"CACHE"           -- ../tab-dev/cache, if ,/sh
if not cache or cache == "" then   -- "" is true in lua, so an
  cache = (os.getenv"HOME" or "~") .. "/tmp/cache" end -- empty
                                   -- CACHE must be caught here
reps  = 20

-- ---- files -----------------------------------------------------------
function exists(f,    h)            -- is f a file we can read?
  h = io.open(f)
  if h then h:close() end
  return h ~= nil end

function home(f)                    -- cache dir, mirroring moot's tree
  return cache .. "/" ..
         (f:match"moot/(.+)%.csv$" or f:match"([^/]+)%.csv$") end

-- ---- cache -----------------------------------------------------------
function pair(tbl,s,    tr,te)      -- rep s's halves of tbl, by seed
  the.seed = 1234567891 + s
  tr, te = tbl:split()
  return tbl:clone(tr), tbl:clone(te) end

function scored(file,who,fun,what,    dir,f,h,tbl,t0,line,ok) -- once
  dir = home(file)
  f   = ("%s/%s.csv"):format(dir, who)
  if exists(f) and not the.force then return f end
  os.execute("mkdir -p " .. dir)
  tbl = Tab(file)
  h    = io.open(f, "w")
  h:write("rep,secs," .. what .. "\n")
  for s = 1, reps do
    t0 = os.clock()
    ok, line = pcall(fun, pair(tbl, s))     -- a broken csv is a skip
    if not ok then h:close(); os.remove(f); error(line, 0) end
    h:write(("%d,%.4f,%s\n"):format(s, os.clock() - t0, line)) end
  h:close()
  return f end

-- ---- scoring ---------------------------------------------------------
function Bag() --> BAG; blank counts, for one test set.
  return new(BAG, {n = 0, ok = 0, got = {}, want = {}, hit = {}}) end

function BAG.tally(i,want,got) --> nil; add one guess to `i`: `want:value`
  i.n          = i.n + 1
  i.ok         = i.ok + (want == got and 1 or 0)
  i.want[want] = (i.want[want] or 0) + 1
  i.got[got]   = (i.got[got] or 0) + 1
  if want == got then i.hit[got] = (i.hit[got] or 0) + 1 end end

function BAG.parts(i,x,    tp,fp,fn) --> int; klass `x:value`'s tp, fp, fn
  tp = i.hit[x] or 0
  fp = (i.got[x] or 0) - tp
  fn = (i.want[x] or 0) - tp
  return tp, fp, fn, i.n - fn - fp - tp end

function BAG.score1(i,x,    tp,fp,fn,tn,r1,f1) --> num; klass `x:value`'s
  tp, fp, fn, tn = i:parts(x)
  r1 = tp / (tp + fn)
  f1 = fp + tn > 0 and fp / (fp + tn) or 0
  return r1, f1, sqrt((1 - r1) ^ 2 + f1 ^ 2) / sqrt(2) end

function BAG.score(i,    k,pd,pf,d2h,r1,f1,d1) --> num; `i`'s macro acc
  k, pd, pf, d2h = 0, 0, 0, 0
  for x in pairs(i.want) do
    r1, f1, d1 = i:score1(x)
    k, pd, pf, d2h = k + 1, pd + r1, pf + f1, d2h + d1 end
  return 100*i.ok/i.n, 100*pd/k, 100*pf/k, d2h/k, k end

function auc(t,    ps,ns,u,j,k,tot) --> num; chance a random positive
  ps, ns = {}, {}                 -- outscores a random negative, given
  for _, p in order(t) do         -- `t`, a list of {score, want:bool}
    u = p[2] and ps or ns; u[#u + 1] = p[1] end
  if #ps == 0 or #ns == 0 then return nil end
  sort(ps); sort(ns)
  j, k, tot = 0, 0, 0             -- cliffs' walk: for each positive,
  for _, x in order(ps) do        -- negatives below, half the ties
    while j < #ns and ns[j+1] <  x do j = j + 1; k = j end
    while k < #ns and ns[k+1] == x do k = k + 1 end
    tot = tot + j + (k - j) / 2 end
  return tot / (#ps * #ns) end

-- ---- stats -----------------------------------------------------------
function Same(xs,ys) --> SAME; sorted copies of two samples, ready
  return new(SAME, {xs = sort(map(xs, same)),  -- to compare
                    ys = sort(map(ys, same))}) end

function SAME.ok(i) --> bool; true if all stats pass
  return i:cohen() <= .35 and i:cliffs() <= .195 and i:ks() <= 1.36 end

function SAME.cohen(i,  a,b,sd) --> num; pooled sds.
  a, b = nums(i.xs), nums(i.ys)
  sd = sqrt(((a.n-1) * a:div()^2 + (b.n-1) * b:div()^2) / (a.n+b.n-2))
  return abs(a.mu - b.mu) / (sd + 1e-32) end

function SAME.cliffs(i,    xs,ys,gt,lt,j,k) --> num; how often `i.xs` is in
  xs, ys, gt, lt, j, k = i.xs, i.ys, 0, 0, 0, 0
  for _, x in order(xs) do
    while j < #ys and ys[j+1] <  x do j = j + 1; k = j end
    while k < #ys and ys[k+1] == x do k = k + 1 end
    gt, lt = gt + j, lt + #ys - k end
  return abs(gt - lt) / (#xs * #ys) end

function SAME.ks(i,    xs,ys,p,q,d,v) --> num; widest gap of two cdfs
  xs, ys, p, q, d = i.xs, i.ys, 0, 0, 0
  while p < #xs and q < #ys do
    v = min(xs[p+1], ys[q+1])
    while p < #xs and xs[p+1] == v do p = p + 1 end
    while q < #ys and ys[q+1] == v do q = q + 1 end
    d = max(d, abs(p/#xs - q/#ys)) end
  return d / sqrt((#xs + #ys) / (#xs * #ys)) end

-- ---- learners --------------------------------------------------------
function bayes(tr,te,    nb,col,bag,trb) -- learn tr, guess all of te
  trb, bag = tr:clone(tr.rows, "bin"), Bag()
  nb, col = Nb(trb, trb.rows), trb.klass
  for _, row in order(tr:clone(te.rows, "bin").rows) do
    bag:tally(row[col.at], nb:guess(row)) end
  return ("%.1f,%.1f,%.1f,%.3f"):format(bag:score()) end

function bayesAuc(tr,te,    trb,nb,col,rows,post,t,sum,k,a) -- macro mean
  trb     = tr:clone(tr.rows, "bin")
  nb, col = Nb(trb, trb.rows), trb.klass
  rows, post = tr:clone(te.rows, "bin").rows, {}
  for _, row in order(rows) do post[row] = nb:posts(row) end
  sum, k = 0, 0
  for x in pairs(nb.subs) do
    t = {}
    for _, row in order(rows) do
      t[#t + 1] = {post[row][x] or 0, row[col.at] == x} end
    a = auc(t)
    if a then sum, k = sum + a, k + 1 end end
  return ("%.4f,%d"):format(k > 0 and sum / k or 0, k) end

function goal(tbl,    col) --> fn; a `fn` that scores one `row`.  For
  col = (the.file or ""):find"/regression/"
        and #tbl.y == 1 and tbl.y[1].it == NUM and tbl.y[1]
  if col then
    return function(row) return tonumber(row[col.at]) or col.mu end end
  return function(row) return tbl:ydist(row) end end

function rmeans(tr,te,    y,lim)    -- the frugal arm: budget labels
  y   = goal(tr)
  lim = the.budget - the.check
  return score(Rmeans(tr, head1(tr.rows, lim), y), te, y) end

function rmeansall(tr,te,    y)     -- the rich arm: every train row
  y = goal(tr)
  return score(Rmeans(tr, tr.rows, y), te, y) end

function head1(rows,n,    out)      -- rows' first n, or all of them
  out = {}
  for j = 1, (#rows < n and #rows or n) do out[j] = rows[j] end
  return out end

function score(model,te,y)          -- where its top 5 sat, and its mae
  return ("%.3f,%.6g"):format(top(model, te, y), mae(model, te, y)) end

function top(model,te,y,    ys,rows,g,best) -- where its top 5 landed
  ys, rows, g = {}, {}, {}
  for n, row in order(te.rows) do
    ys[n], rows[n], g[row] = y(row), row, model:guess(row) end
  for n, row in order(rows, function(a,b) return g[a] < g[b] end) do
    if n > the.check then break end
    best = (not best or y(row) < best) and y(row) or best end
  for n, v in order(ys, lt) do
    if v == best then return 100 * (n-1) / max(1, #ys-1) end end
  return 100 end

function mae(model,te,y,    num)    -- mean error of model's guesses
  num = Num()
  for _, row in order(te.rows) do
    num:add(abs(model:guess(row) - y(row))) end
  return num.mu end

-- ---- reading it back -------------------------------------------------
function dirs(kind,    out,h)       -- every cached set of this kind
  out, h = {}, io.popen("find " .. cache .. "/" .. (kind or "") ..
                        " -name '*.csv' 2>/dev/null")
  for line in h:lines() do out[line:match"^(.*)/"] = true end
  h:close()
  return sorted(out) end

function sorted(t,    u)            -- t's keys, in order
  u = {}
  for k in pairs(t) do u[#u + 1] = k end
  return sort(u) end

function readcol(dir,who,what,    f,out,at,n) -- one result column
  f = io.open(("%s/%s.csv"):format(dir, who))
  if not f then return nil end
  out = {}
  for line in f:lines() do
    n = 0
    for s in line:gmatch"[^,]+" do
      n = n + 1
      if not at and s == what then at = n end
      if at and n == at then out[#out + 1] = tonumber(s) end end end
  f:close()
  return #out > 0 and out or nil end

function mid(xs,    ys)             -- the median of xs
  ys = sort(map(xs, same))
  return #ys == 0 and 0 or (#ys % 2 == 1 and ys[(#ys+1)/2]
                            or (ys[#ys/2] + ys[#ys/2+1]) / 2) end

function versus(kind,who1,who2,what,big,    w,t,l,ma,mb,xs,ys)
  w, t, l, ma, mb = 0, 0, 0, {}, {}
  for _, dir in order(dirs(kind)) do
    xs, ys = readcol(dir, who1, what), readcol(dir, who2, what)
    if xs and ys then
      ma[#ma+1], mb[#mb+1] = mid(xs), mid(ys)
      if Same(xs, ys):ok()             then t = t + 1
      elseif (mid(xs) > mid(ys)) == big then w = w + 1
      else                                  l = l + 1 end end end
  print(("%-11s %-10s %7.3f   %-10s %7.3f   %d win %d tie %d loss")
        :format(kind, who1, mid(ma), who2, mid(mb), w, t, l)) end

-- ---- start up --------------------------------------------------------
function slow.splits(    tbl,tr,te)   -- what seed s gives
  tbl = Tab(the.file)
  tr, te = pair(tbl, tonumber(the.rep) or 1)
  print(#tr.rows, #te.rows, table.concat(tr.rows[1], ",")) end

function slow.report()                -- what the cache says
  versus("classify",   "nb",     "lgbm",      "acc",  true)
  versus("regression", "rmeans", "lgbm",      "mae",  false)
  versus("regression", "rmeans", "rmeansall", "rank", false)
  versus("optimize",   "rmeans", "rmeansall", "rank", false) end

function slow.nb()
  print(scored(the.file, "nb", bayes, "acc,pd,pf,d2h")) end

function slow.nbauc()
  print(scored(the.file, "nbauc", bayesAuc, "auc,klasses")) end

function slow.rmeans()
  print(scored(the.file, "rmeans", rmeans, "rank,mae")) end

function slow.rmeansall()
  print(scored(the.file, "rmeansall", rmeansall, "rank,mae")) end

the = cli()                 -- read late, so that a bare `rmeans` is
                            -- an action of slow, and not a file name
if (arg and arg[0] or ""):find"tab%-eg%.lua$" and the.go then
  fun = slow[the.go] or fast[the.go]   -- a broken csv is a skip, not a
  if not fun then                   -- stop; an unknown go says so
    io.stderr:write("tab-eg.lua: no such go: ", the.go, "\n")
  else
    ok, err = pcall(fun)
    if not ok then
      io.stderr:write(the.file, ": ", tostring(err), "\n") end end end
return _ENV
