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

-- The same label budget as `rmeans`, spent on rows `acquire` chose
-- rather than on the first 45 a shuffle handed over.  It has no y
-- model, so there is no mae to report -- but `top` only ever asks
-- `guess` for an ORDER, so acquire's own key stands in: a test row
-- scores low when it sits near `best`'s middle and far from `rest`'s,
-- and `top` labels the five lowest.  Lower is better, as it is for a
-- predicted y, so `top` needs no change.  `acquire` is handed the
-- same `y` `top` scores with: left on its ydist default it would
-- chase the opposite end of every regression set (see tab.yue).
function acq(tr,te,    y,best,rest,bmid,rmid,ys)
  y = goal(tr)
  _, best, rest = acquire(tr, the.budget - the.check, y)  -- `y`, not
  bmid, rmid = best:mids(), rest:mids()
  best, ys = top5y(
    {guess = function(_,row) return tr:xdist(row,bmid)
                                  - tr:xdist(row,rmid) end}, te, y)
  return ("%.3f,%d"):format(pct(best, ys), gap(best, ys)) end

-- `acq` with the acquiring taken out.  Grab the first 45 rows a
-- shuffle hands over, label every one, call the best sqrt(45) of them
-- `best` and the remainder `rest`, and rank the test set on that same
-- near-best/far-rest key.  Same budget, same split, same scoring --
-- the only thing missing is the CHOOSING.  So whatever `acq` scores
-- above this is what the acquisition step is worth and nothing else;
-- if the two land together, the steering bought nothing and `rmeans`
-- and `acq` were only ever being compared on their models.
function grab(tr,te,    y,pool,got,k,best,rest,bmid,rmid,ys)
  y    = goal(tr)
  pool = shuffle(map(tr.rows, same))   -- a copy, never `tr.rows`
  got  = {}
  for j = 1, math.min(the.budget - the.check, #pool) do
    got[j] = pool[j] end
  -- `acquire` ends holding the top sqrt(n) by y in `best`; land in
  -- the same place, so the two arms differ in how the 45 were picked
  -- and in nothing downstream of that.
  sortBy(got, y)
  k = math.floor((#got) ^ .5)   -- `^` binds tighter than `#`
  best, rest = tr:clone(), tr:clone()
  for j, row in order(got) do
    if j <= k then best:add(row) else rest:add(row) end end
  bmid, rmid = best:mids(), rest:mids()
  best, ys = top5y(
    {guess = function(_,row) return tr:xdist(row,bmid)
                                  - tr:xdist(row,rmid) end}, te, y)
  return ("%.3f,%d"):format(pct(best, ys), gap(best, ys)) end

-- Full ezr: `acquire` picks the 45, then a SOLO tree models them.
-- `acq` above reads those same 45 as two centroids and ranks on the
-- distance between them; this reads them as a tree and ranks on the
-- mean y of the leaf a test row lands in.  Same rows, same budget,
-- two different readings -- so the gap between the two arms is what
-- the tree adds over the centroids and nothing else.
--
-- `Tree`, not `Forest`.  A forest bootstraps (`some(rows,#rows)`, with
-- replacement) and redraws sqrt(#x) columns at every node: both are
-- variance bought for an ensemble's benefit, and a solo tree only
-- pays for them -- the bootstrap alone would cost ~17 of the 45 rows.
-- So: every row, `cols=0` for every column, and the entropy cut
-- itself is reused untouched rather than written a second time.
function acqtree(tr,te,    y,rows,bt,tree)
  y          = goal(tr)
  rows       = acquire(tr, the.budget - the.check, y)
  bt         = binTab(tr, rows, y)
  tree       = Tree(bt, bt.rows, 1, 0)
  return score({guess = function(_,row,    v)
    v = leafmean(tree:pick(row), y)
    return v or 0 end}, te, y) end

-- ---- acquire, one model per klass ------------------------------------
-- `acquire` in tab.yue ranks rows against ONE best/rest pair, which is
-- what a single continuous goal wants.  A klass column has no such
-- order, so here every klass runs its own one-vs-rest pair and the
-- picks rotate between them.  One label serves every pair at once --
-- a row of klass x is `best` for x and `rest` for all the others --
-- so the seed costs labels in the number of klasses, not twice that.

-- tab.yue:752 sorts all of `todo` on each pass and then uses one row
-- of it.  Scan instead: one O(n) pass keeping the running best names
-- the same row for less work, and drops the stable-sort machinery.
function pick1(todo,on,    v,b,at) --> row; and take it out of `todo`
  b = -math.huge
  for j, z in order(todo) do
    v = on(z)
    if v > b then b, at = v, j end end
  return table.remove(todo, at) end

function klassesIn(got,at,    u,ks) --> list; klasses labelled so far
  u, ks = {}, {}
  for _, row in order(got) do u[row[at]] = true end
  for x in pairs(u) do ks[#ks + 1] = x end
  return sort(ks, function(a,b) return tostring(a) < tostring(b) end) end

-- Rebuild klass `x`'s two middles from every label held so far.  An
-- incremental best/rest cannot work here: a klass first seen on label
-- 30 would have missed labels 1..29, and at <= 45 labels the rebuild
-- costs nothing.
function klassMids(tr,got,x,    b,r) --> bmid, rmid
  b, r = tr:clone(), tr:clone()
  for _, row in order(got) do
    if row[tr.klass.at] == x then b:add(row) else r:add(row) end end
  return b:mids(), r:mids() end

-- Seed.  Reading a klass costs a label, so the only lawful way to go
-- looking for a second klass is to keep labelling -- peeking at an
-- unlabelled row's klass to pick a contrast would be cheating.  So
-- take the next seed as far in x from everything already labelled as
-- the pool allows: that IS the "not close" check (two rows sitting on
-- top of each other leave `bmid - rmid` nothing to separate), and it
-- is also the best odds of landing on a klass not yet seen.  Stop as
-- soon as two distinct klasses are in hand.
function seed1(tr,todo,got,cap,    far)
  got[#got + 1] = table.remove(todo)
  while #todo > 0 and #got < cap
        and #klassesIn(got, tr.klass.at) < 2 do
    got[#got + 1] = pick1(todo, function(z,    d)
      d = math.huge
      for _, row in order(got) do
        far = tr:xdist(z, row)
        if far < d then d = far end end
      return d end) end end

function acquired(tr,    cap,todo,got,ks,j,x,bm,rm) --> list; the labels
  cap  = the.budget - the.check
  todo = head1(shuffle(map(tr.rows, same)), the.few)
  got  = {}
  seed1(tr, todo, got, cap)
  j = 0
  while #todo > 0 and #got < cap do
    ks = klassesIn(got, tr.klass.at)
    if #ks < 2 then                 -- seed never found a second klass:
      got[#got + 1] = table.remove(todo)   -- no pair to steer by, so
    else                                   -- spend what is left blind
      j = j % #ks + 1               -- rotate, so the labels stay even
      x = ks[j]                     -- over the klasses found so far
      bm, rm = klassMids(tr, got, x)
      got[#got + 1] = pick1(todo, function(z)
        return tr:xdist(z, rm) - tr:xdist(z, bm) end) end end
  return got end

-- Naive Bayes over an acquired budget, against the same over a random
-- one: the pair isolates what the acquiring buys, since `nb` itself
-- trains on every row.
function nbrows(tr,te,rows,    trb,nb,col,bag)
  trb, bag = tr:clone(rows, "bin"), Bag()
  nb, col  = Nb(trb, trb.rows), trb.klass
  for _, row in order(tr:clone(te.rows, "bin").rows) do
    bag:tally(row[col.at], nb:guess(row)) end
  return Acc:format(bag:score()) end

function acqnb(tr,te) return nbrows(tr, te, acquired(tr)) end

function rndnb(tr,te)
  return nbrows(tr, te,
                head1(shuffle(map(tr.rows, same)), the.budget - the.check)) end

function head1(rows,n,    out)      -- rows' first n, or all of them
  out = {}
  for j = 1, (#rows < n and #rows or n) do out[j] = rows[j] end
  return out end

-- The y of the best row in `model`'s top `the.check` guesses, with
-- every y in `te` sorted beside it.  One pass: `guess` runs over the
-- test set once however many ways the caller then reads the answer.
function top5y(model,te,y,    ys,rows,g,best) --> num, list
  ys, rows, g = {}, {}, {}
  for n, row in order(te.rows) do
    ys[n], rows[n], g[row] = y(row), row, model:guess(row) end
  for n, row in order(rows, function(a,b) return g[a] < g[b] end) do
    if n > the.check then break end
    best = (not best or y(row) < best) and y(row) or best end
  return best, sort(ys, lt) end

function pct(best,ys,    n,v)       -- `best`'s percentile within `ys`
  for n, v in order(ys, lt) do
    if v == best then return 100 * (n-1) / max(1, #ys-1) end end
  return 100 end

-- 100 = we found the best row, 0 = we did no better than an average
-- one, below 0 = worse than average.  `pct` counts HOW MANY rows beat
-- us, which saturates: on a set where hundreds of rows sit a hair
-- apart, being 200th is a fine answer scored as a bad one.  This
-- counts how much y we gave up instead, which is the thing an
-- optimizer actually spends, and it is unitless so sets compare.
function gap(best,ys,    lo,mu,v)
  lo, mu = ys[1], 0
  for _, v in order(ys) do mu = mu + v end
  mu = mu / #ys
  if mu == lo then return 100 end   -- every row the same y: nothing lost
  return math.floor(100 * (1 - (best - lo) / (mu - lo))) end

function top(model,te,y,    best,ys)  -- where its top 5 landed
  best, ys = top5y(model, te, y)
  return pct(best, ys) end

function win(model,te,y,    best,ys)  -- how much of the gap it closed
  best, ys = top5y(model, te, y)
  return gap(best, ys) end

function score(model,te,y,    best,ys)  -- its top 5 two ways, and mae
  best, ys = top5y(model, te, y)
  return ("%.3f,%d,%.6g"):format(pct(best, ys), gap(best, ys),
                                 mae(model, te, y)) end

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

function slow.acqnb()
  print(scored(the.file, "acqnb", acqnb, AccCols)) end

function slow.rndnb()
  print(scored(the.file, "rndnb", rndnb, AccCols)) end

function slow.nbauc()
  print(scored(the.file, "nbauc", bayesAuc, AucCols)) end

-- ---- the forest, pointed at a continuous goal ------------------------
-- Not a regression tree.  The SPLIT is still the classifier tab
-- already has: binarize the labelled rows into "better half" vs
-- "rest" and let the entropy cut do what it does.  Only the LEAF is
-- read differently -- the mean `y` of the rows that reached it.
-- Deep trees (depth=12 leaf=2) put ~2 rows in a leaf, so 30 of those
-- averaged is a near-continuous score.  A vote share would not be:
-- it offers `rounds+1` values to rank by, which is exactly why the
-- FFT arm could not rank (tab-dev/CLAUDE.md).
function binTab(tbl,rows,y,    ys,mid,names,out,t) --> TAB, +1 klass col
  ys = {}
  for _, row in order(rows) do ys[#ys+1] = y(row) end
  sort(ys, lt)
  mid = ys[math.floor(#ys / 2) + 1] or 0
  names = {}
  for k, s1 in order(tbl.names) do names[k] = s1 end
  names[#names+1] = "best!"       -- last `!` wins, so this is the klass
  out = {names}                   -- and the real y columns stay y
  for _, row in order(rows) do
    t = {}
    for k = 1, #tbl.names do t[k] = row[k] end
    t[#t+1] = y(row) <= mid and "y" or "n"
    out[#out+1] = t end
  return Tab(out) end

function leafmean(leaf,y,    a,c)  -- num; mean y of a leaf's rows
  a, c = 0, 0
  for _, r in order(leaf.rows) do a, c = a + y(r), c + 1 end
  return c > 0 and a / c or nil end

function fornum(tr,te,rows,    y,fst)  -- forest over `rows` of `tr`
  y   = goal(tr)
  fst = Forest(binTab(tr, rows, y), nil, the.rounds)
  return score({guess = function(_,row,    s,n,v)
    s, n = 0, 0
    for _, m in order(fst.all) do
      v = leafmean(m:pick(row), y)
      if v then s, n = s + v, n + 1 end end
    return n > 0 and s / n or 0 end}, te, y) end

function fornumall(tr,te) return fornum(tr, te, tr.rows) end
function fornum45(tr,te)
  return fornum(tr, te, head1(tr.rows, the.budget - the.check)) end

function slow.acq()
  print(scored(the.file, "acq", acq, "rank,win")) end

function slow.grab()
  print(scored(the.file, "grab", grab, "rank,win")) end

function slow.acqtree()
  print(scored(the.file, "acqtree", acqtree, "rank,win,mae")) end

function slow.fornumall()
  print(scored(the.file, "fornumall", fornumall, "rank,win,mae")) end

function slow.fornum45()
  print(scored(the.file, "fornum45", fornum45, "rank,win,mae")) end

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
