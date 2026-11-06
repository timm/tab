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
BAG, SAME = {}, {}   -- the classes defined below
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
  seed(1234567891 + s)
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
-- The two score headers, named once, so an arm cannot write a column
-- order its reader does not expect.
Acc     = "%.1f,%.1f,%.1f,%.3f,%.1f,%.1f,%.3f,%d"
AccCols = "acc,pd,pf,d2h,macropd,macropf,macrod2h,klasses"
AucCols = "auc,klasses,macroauc"

-- ---- (scoring) ---------------------------------------------------------
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

-- `fp + tn` is `i.n - i.want[x]`, so it is zero exactly when every test
-- row is klass `x`.  Then `x` has no negatives, there is no false alarm
-- rate to report, and `pf` and the `d2h` built on it come back nil --
-- not zero, which would score a measurement that does not exist as a
-- perfect one.  `pd` is still fine: it only needs positives.
function BAG.score1(i,x,    tp,fp,fn,tn,r1,f1) --> num; klass `x:value`'s
  tp, fp, fn, tn = i:parts(x)
  r1 = tp / (tp + fn)
  if fp + tn == 0 then return r1 end
  f1 = fp / (fp + tn)
  return r1, f1, sqrt((1 - r1) ^ 2 + f1 ^ 2) / sqrt(2) end

function BAG.klasses(i) return keys(i.want) end --> list; sorted, so
                                     -- the sums below add in one order

-- Return `i`'s accuracy, then pd, pf and d2h weighted by klass
-- frequency, then the same three averaged equally over klasses, then
-- the klass count.  Two averages, because they answer two questions:
-- the weighted one asks how the learner does on a row drawn from this
-- data, the macro one how it does on a klass drawn from its klasses.
-- Under imbalance they part company hard, and a rare klass the model
-- never names costs the macro mean its whole share and the weighted
-- mean almost nothing.
--
-- The weighted pd is the accuracy.  sum_x (n_x/n)(tp_x/n_x) is
-- sum_x tp_x / n, so the two agree by construction, not by luck of
-- this data.  Reported anyway, so `pd` means one thing in every
-- column of every chart and the identity is on the page.
--
-- The klass count is reported last, and it is the reader's sentinel for
-- the `pf` and `d2h` columns: a one-klass test split leaves every klass
-- without negatives, so those four columns are written 0 and mean
-- nothing.  Gate on `klasses > 1` before using them -- the same bargain
-- `AucCols` already makes with its own `klasses`.  It is all or nothing:
-- the guard in `score1` fires for klass `x` only when `x` is the whole
-- test set, which no second klass can survive.  So the weighted sums
-- below still divide by `i.n`.
function BAG.score(i,    k,pd,pf,d2h,wd,wf,wh,w,r1,f1,d1) --> num
  k, pd, pf, d2h, wd, wf, wh = 0, 0, 0, 0, 0, 0, 0
  for _, x in order(i:klasses()) do
    r1, f1, d1 = i:score1(x)
    w          = i.want[x]
    k, pd, wd  = k + 1, pd + r1, wd + w*r1
    if f1 then
      pf, d2h = pf + f1, d2h + d1
      wf, wh  = wf + w*f1, wh + w*d1 end end
  return 100*i.ok/i.n, 100*wd/i.n, 100*wf/i.n, wh/i.n,
         100*pd/k, 100*pf/k, d2h/k, k end

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

-- Return `t`'s keys, sorted on `tostring`.  Every klass walk that
-- feeds a sum needs this: `pairs` has no order, float addition is not
-- associative, and the two together make a score that drifts between
-- ports and between runs.
function keys(t,    ks) --> list
  ks = {}
  for k in pairs(t) do ks[#ks+1] = k end
  return sort(ks, function(a,b) return tostring(a) < tostring(b) end) end

-- Return `auc,klasses,macroauc` over `cols`, one {score,want} list
-- per klass -- the same list `auc` above takes.  The weighted mean
-- leans on the klasses that actually show up; the macro mean beside
-- it is what every earlier run reported.
--
-- A klass with no positives, or none negative, has no auc in this
-- split at all, so it is dropped and the weights renormalise over
-- what is left (`w`, not `#cols`).  Weighting a measurement that does
-- not exist would be scoring a gap as though it were a result.
function aucline(cols,    a,nk,tot,w,mac,sum) --> str
  tot, w, mac = 0, 0, {}
  for _, c in order(cols) do
    a = auc(c)
    if a then
      nk = 0
      for _, p in order(c) do if p[2] then nk = nk + 1 end end
      tot, w   = tot + nk * a, w + nk
      mac[#mac+1] = a end end
  if #mac == 0 then return "0,0,0" end
  sum = 0
  for _, x in order(mac) do sum = sum + x end
  return ("%.4f,%d,%.4f"):format(tot/w, #mac, sum/#mac) end

-- ---- stats -----------------------------------------------------------
function Same(xs,ys) --> SAME; sorted copies of two samples, ready
  return new(SAME, {xs = sort(map(xs, same)),  -- to compare
                    ys = sort(map(ys, same))}) end

function SAME.ok(i) --> bool; true if all stats pass
  return i:cohen() <= .35 and i:cliffs() <= .195 and i:ks() <= 1.36 end

function SAME.cohen(i,  a,b,sd) --> num; pooled sds.
  a, b = adds(i.xs), adds(i.ys)
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
  return Acc:format(bag:score()) end

function bayesAuc(tr,te,    trb,nb,col,rows,post,t,cols) --> str
  trb     = tr:clone(tr.rows, "bin")
  nb, col = Nb(trb, trb.rows), trb.klass
  rows, post = tr:clone(te.rows, "bin").rows, {}
  for _, row in order(rows) do post[row] = nb:posts(row) end
  cols = {}
  for _, x in order(nb:klasses()) do        -- sorted, not `pairs`
    t = {}
    for _, row in order(rows) do
      t[#t + 1] = {post[row][x] or 0, row[col.at] == x} end
    cols[#cols + 1] = t end
  return aucline(cols) end

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
  print(scored(the.file, "nb", bayes, AccCols)) end

function slow.nbauc()
  print(scored(the.file, "nbauc", bayesAuc, AucCols)) end

function slow.rmeans()
  print(scored(the.file, "rmeans", rmeans, "rank,mae")) end

function slow.rmeansall()
  print(scored(the.file, "rmeansall", rmeansall, "rank,mae")) end

if (arg and arg[0] or ""):find"tab%-eg%.lua$" then
  the = cli()               -- read late, so that a bare `rmeans` is an
  if the.go then            -- action of slow, and not a file name; and
    fun = slow[the.go] or eg[the.go]  -- read only when this is the
    if not fun then         -- main script, since a required tab-eg
      io.stderr:write("tab-eg.lua: no such go: ", the.go, "\n")
    else                    -- would eat its caller's own actions
      ok, err = pcall(fun)  -- a broken csv is a skip, not a stop
      if not ok then
        io.stderr:write(tostring(the.file), ": ", tostring(err), "\n")
        end end end end
return _ENV
