-- <!--- vim: set ts=2 sw=2 sts=2 et cc=75 : -->
-- tab.yue: tab.lua, ported to yuescript.  Same algorithm, same
-- golden values.  Three lua idioms go away: the `_ENV` trick (yue
-- builds the export table at the foot), the scratch-parameter locals
-- (yue scopes a local at its first assignment), and the explicit
-- `self` (yue's `=>` and `@`).  What replaces them is listed in the
-- notes at the foot of this file.
--
-- One yue hazard, for whoever edits this next: an assignment to a
-- name already local in an enclosing scope writes THAT name.  So a
-- function that wants its own `near` must say `local near` first, or
-- it will overwrite the module's `near` test helper.  Marked below.

local rng
local the, help, floor, exp, sqrt, log, abs, min, max, TAB, NUM, SYM, RMEANS, NB, TREE, FOREST, values, csv, Col, Sym, Num, Tab, ThisC, ThatC, Hist, clog, ent, sc, binRows, tally, hist, Rmeans, Nb, Tree, Forest, new, cli, seed, rint, shuffle, some, Drawn, pick, map, sum, adds, best, same, lt, sort, order, o, print, fmt, logfmt, about, eg, slow, near, ok, run, halves, main

the = { }
help = [[tab: a good guess from a few dozen labels.
Range means, shrunk to the grand mean, weighed by variance.
(c) 2026 Tim Menzies <timm@ieee.org> MIT license.

usage: luajit tab.lua [name=value | action | file.csv ...]

flags:
  version=0.6.0    version number
  bins=7           numeric columns get this many bins
  budget=50        labels, all in
  check=5          of those, saved for the test rows
  fmt=%.2f         how a fraction is printed
  cuts=50          bins per numeric column (rounded up to odd)
  depth=12         how deep a tree may grow
  leaf=2           rows each side of a cut needs
  m=2              m-estimate: prior weight for a thin bin
  p=2              minkowski coefficient
  reps=3           repeats, when something is timed
  rounds=30        trees in a forest
  seed=1234567891  random number seed
  test=None        held-out csv (None: demos test on train)
  train=~/gits/moot/optimize/misc/auto93.csv

actions:
   -h              print help
   --all           every fast action (--num, --split ... run one)

Any flag above can lead an action, so `seed=1 --split` is a thing.]]

floor, exp, sqrt, log = math.floor, math.exp, math.sqrt, math.log
abs, min, max = math.abs, math.min, math.max

TAB, NUM, SYM, RMEANS, NB, TREE, FOREST = { }, { }, { }, { }, { }, { }, { }

-- ---- values ---------------------------------------------------------
values = function(s)
  local u = { }
  for s1 in (s .. ","):gmatch("(.-),") do
    local v = s1:match("^%s*(.-)%s*$")
    u[#u + 1] = tonumber(v) or v
  end
  return u
end

csv = function(file)
  local rows = { }
  local path = file:gsub("^~", os.getenv("HOME") or "~")
  for line in io.lines(path) do
    local s = line:match("^%s*(.-)%s*$")
    if s ~= "" and s:sub(1, 1) ~= "#" then
      rows[#rows + 1] = values(s)
    end
  end
  return rows
end

-- ---- columns --------------------------------------------------------
Col = function(txt, at)
  return (txt:find("^%u") and Num or Sym)(txt, at)
end

Sym = function(txt, at)
  return new(SYM, {
    txt = txt or "S",
    at = at or 0,
    n = 0,
    has = { },
    cl = 0
  })
end

-- `@cl` is sum(c*log c) over the counts, kept up to date here so
-- `div` need not walk `@has` at all.  Two reasons.  Order: `pairs`
-- has none and floating point addition is not associative, so a sum
-- taken in hash order makes an entropy's last bits -- and so a tie
-- between two cuts -- turn on how the table laid itself out, and
-- (measured) the same seed then grew a different forest run to run.
-- Cost: a cut sweep calls `add` twice and `div` twice per candidate,
-- so paying two logs here beats paying one per klass there.
SYM.add = function(self, v, inc)
  if not (v == "?") then
    inc = inc or 1
    self.n = self.n + inc
    local c = self.has[v] or 0
    if c > 0 then
      self.cl = self.cl - (c * log(c))
    end
    c = c + inc
    if c <= 0 then
      self.has[v] = nil
    else
      self.has[v] = c
      self.cl = self.cl + (c * log(c))
    end
  end
  return v
end

-- H = -sum (c/n) log(c/n) = log n - (1/n) sum c log c, and `add`
-- already holds that inner sum, so this is arithmetic, not a walk.
SYM.div = function(self)
  return self.n < 1 and 0 or max(0, log(self.n) - self.cl / self.n) / log(2)
end

-- The mode, with a tie broken on `tostring` -- once per node, not
-- once per candidate cut, so the sort is affordable and `pairs`
-- order (which differs between ports) never decides a leaf's label.
SYM.mid = function(self)
  local ks = { }
  for v in pairs(self.has) do
    ks[#ks + 1] = v
  end
  sort(ks, function(x, y)
    return tostring(x) < tostring(y)
  end)
  local bk
  local b = -1
  for _, v in order(ks) do
    if self.has[v] > b then
      b, bk = self.has[v], v
    end
  end
  return bk
end

SYM.norm = function(self, v)
  return v
end
SYM.holds = function(self, x, v)
  return x == "?" or x == v
end
SYM.bin = function(self, v)
  return v
end

SYM.nVals = function(self)
  self.kinds = self.kinds or max(2, sum(self.has, function()
    return 1
  end))
  return self.kinds
end

Num = function(txt, at)
  return new(NUM, {
    txt = txt or "N",
    at = at or 0,
    n = 0,
    mu = 0,
    m2 = 0,
    w = ((txt or ""):find("%-$") and 0 or 1)
  })
end

NUM.add = function(self, v, inc)
  if not (v == "?") then
    inc = inc or 1
    self.n = self.n + inc
    if self.n <= 0 then
      self.n, self.mu, self.m2 = 0, 0, 0
    else
      local d = v - self.mu
      self.mu = self.mu + (inc * d / self.n)
      self.m2 = self.m2 + (inc * d * (v - self.mu))
    end
  end
  return v
end

NUM.div = function(self)
  return self.n < 2 and 0 or sqrt(max(self.m2, 0) / (self.n - 1))
end
NUM.mid = function(self)
  return self.mu
end
NUM.holds = function(self, x, v)
  return x == "?" or x <= v
end
-- cut never loses a row
NUM.bin = function(self, v)
  if v == "?" then
    return v
  end
  local b = 1 + floor(the.bins * self:norm(v))
  return b > the.bins and the.bins or b
end

NUM.norm = function(self, v)
  if v == "?" then
    return v
  end
  local z = (v - self.mu) / (self:div() + 1e-32)
  z = z > 3 and 3 or (z < -3 and -3 or z)
  return 1 / (1 + exp(-1.7 * z))
end

-- Offer `out` one cut between each pair of distinct sorted neighbours:
-- sort once, grow `this` left to right while `that` sheds the same.
-- ---- tables ---------------------------------------------------------
Tab = function(src)
  return adds(src, new(TAB, {
    rows = { },
    names = { },
    cols = { },
    x = { },
    y = { }
  }))
end

TAB.add = function(self, row)
  if #self.cols == 0 then
    return self:head(row)
  end
  self.rows[#self.rows + 1] = row
  for _, col in order(self.cols) do
    col:add(row[col.at])
  end
  return row
end

TAB.head = function(self, names)
  self.names = names
  for at, txt in order(names) do
    local col = Col(txt, at)
    self.cols[#self.cols + 1] = col
    if not txt:find("X$") then
      if txt:find("[-+!]$") then
        self.y[#self.y + 1] = col
        if txt:find("!$") then
          self.klass = col
        end
      else
        self.x[#self.x + 1] = col
      end
    end
  end
  return nil
end

TAB.clone = function(self, rows, how)
  local head = how and map(self.cols, function(col)
    return col.txt:lower()
  end) or self.names
  local out = {
    head
  }
  for _, row in order((rows or { })) do
    if how then
      out[#out + 1] = map(self.cols, function(col)
        return col[how](col, row[col.at])
      end)
    else
      out[#out + 1] = row
    end
  end
  return Tab(out)
end

TAB.mid = function(self, cols)
  local u = { }
  for _, col in order((cols or self.cols)) do
    u[col.txt] = col:mid()
  end
  return u
end

TAB.ydist = function(self, row)
  local on
  on = function(col)
    return abs(col:norm(row[col.at]) - col.w) ^ the.p
  end
  return (sum(self.y, on) / #self.y) ^ (1 / the.p)
end

TAB.split = function(self)
  local rows = shuffle(map(self.rows, same))
  local n = floor(.8 * #rows)
  local u1, u2 = { }, { }
  local t = u1
  for j, row in order(rows) do
    if j > n then
      t = u2
    end
    t[#t + 1] = row
  end
  return u1, u2
end

-- Offer `out` every cut of every x column over `rows`: `ks` is one
-- y per row; `Y` collects them, so what "least diversity" means --
-- Num and sd, or Sym and entropy -- is the caller's choice.
-- ---- histogram cut ---------------------------------------------
-- The same binned search, counted instead of accumulated.
--
-- The search this replaced built a `Sym` for each side of a cut and
-- walked every row through both; each `Sym.add` hashes a
-- klass string and keeps an entropy cache -- `cl + c*log c` --
-- current, so it spent a `log` per row per column per node.  The
-- profile put 53% of a run in there, and the sort before it 55% of
-- the run before THAT.
--
-- Counting instead: one integer per (bin, klass).  The klass strings
-- are coded to integers ONCE per node, so the inner loop never
-- hashes a string; entropy is computed from the counts at the bin
-- boundaries only, and updated for just the klasses a bin actually
-- holds.  For 1000 rows and 2 klasses that is ~3000 `log` calls
-- replaced by a few hundred.
--
-- Scratch, hoisted out of the search and reused.  These hold no
-- answers: they are buffers, kept at module level so a node pays for
-- them once a run instead of once a column.  That is the whole
-- speedup -- the old search was 45% garbage collection, and a fresh
-- table per column per node of a 30-tree forest was the garbage.
--
-- Nothing here outlives one column, and each is cleared by its own
-- writer before use.
--
-- The price is that the search must not reenter itself: one `cut` has
-- to finish before the next begins, or these three quietly corrupt.
-- `TREE.grow` obeys that -- it takes its cut, then recurses -- and a
-- threaded forest would not.
ThisC, ThatC, Hist = { }, { }, { }

-- ---- binning, on the column itself --------------------------------
-- A column knows its own bins.  `slot` puts a value in one, `edge`
-- turns a bin back into the threshold to report, `slots` says how
-- many there are.  Numeric edges come off the summary the column
-- already keeps, so they are computed once and then shared by every
-- tree and every node of the ensemble -- which is the whole trick:
-- nothing is sorted, and nothing is re-derived per node.
-- The count is forced odd: `slot` clamps to `-hi..hi` and shifts, so
-- there are always `2*hi+1` bins -- one centred on the mean, `hi` to
-- each side.  `slots` must report that, not `the.cuts`, or the bin a
-- 3sd outlier pins to falls outside the range `tally` clears and
-- picks up a stale count.  `cuts=50` and `cuts=51` are the same 51.
NUM.slots = function(self)
  return 2 * floor(the.cuts / 2) + 1
end
NUM.edge = function(self, b)
  return self.mu + (b - self.hi - 0.5) * self.r
end
NUM.slot = function(self, x)
  if not self.r then
    self.hi = floor(the.cuts / 2)
    self.r = 3 * self:div() / self.hi
  end
  if x == "?" or self.r <= 0 then
    return nil
  end
  local b = floor((x - self.mu) / self.r + 0.5)
  return (b < -self.hi and -self.hi or (b > self.hi and self.hi or b)) + self.hi + 1
end

-- A symbolic column's bins are its own values, indexed once, sorted
-- so a tie falls where it always did.
SYM.index = function(self, vs, v, n)
  if not self.vi then
    vs = { }
    for v in pairs(self.has) do
      vs[#vs + 1] = v
    end
    sort(vs, function(a, b)
      return tostring(a) < tostring(b)
    end)
    self.vi, self.vs = { }, vs
    for n = 1, #vs do
      self.vi[vs[n]] = n
    end
  end
  return self.vi
end
SYM.slots = function(self)
  return self:index() and #self.vs
end
SYM.edge = function(self, b)
  return self.vs[b]
end
SYM.slot = function(self, x)
  return x ~= "?" and self:index()[x] or nil
end

-- ---- the histogram ------------------------------------------------
-- `SYM.div` is `(log n - cl/n)/log 2` with `cl = sum c*log c`, so a
-- count that moves changes exactly one term of cl.  Keeping cl
-- current costs two `log`s per changed klass per bin, where walking
-- the rows cost one per row.
clog = function(c)
  return c > 0 and c * log(c) or 0
end

-- Entropy of `n` rows whose `sum c*log c` is `cl`, in nats: the
-- `/log 2` comes out once, in the score.
ent = function(n, cl)
  return max(0, log(n) - cl / n)
end

-- `n` rows split `this`/`that` score as their sizes weigh their
-- entropies -- the same quantity `TAB.cut` used to get from two
-- `Sym`s, verified equal to `Sym.div` to 2.7e-15.
sc = function(nn, tcl, on, ocl)
  return (ent(nn, tcl) * nn + ent(on, ocl) * on) / (log(2) * (nn + on))
end

-- Bin every x value of `tbl` once and keep the id past the end of the
-- row.  A bin id is a function of (row, column) alone -- it does not
-- depend on which rows a node happens to hold -- and `Forest` hands
-- all its trees the same tbl and the same row tables.  Without this,
-- one id is recomputed 34 to 71 times a build (measured, four sets).
-- With it, `tally`'s inner loop is an add and a read: no method
-- dispatch, no arithmetic, and no NUM/SYM branch.
--
-- Two things make writing into the row safe.  Nothing anywhere reads
-- `#row`, so the extra cells are invisible to the rest of the code;
-- and `clone` builds a fresh TAB, so `binAt` belongs to this table.
-- The ROWS, though, are shared with whatever table they came from:
-- two tables binning the same rows would write the same slots and the
-- last would win.  Hence one entry point, `TAB.cut`, and a guard --
-- and hence `tbl.rows`, not a node's subset, which is also what makes
-- it once a run rather than once a node.
-- The klass rides along, for the same reason and in the same place:
-- the search wants it as a small int, and a node that read the string
-- would hash it once per row per column.  Its slot is free -- the
-- klass is a y column, so no x column claims `off + klass.at`.
-- `kodes` is the way back, which `mid` and `posts` still need.
binRows = function(tbl)
  if tbl.binned then
    return
  end
  tbl.binned = true
  local off = #tbl.cols
  local _list_0 = tbl.x
  for _index_0 = 1, #_list_0 do
    local col = _list_0[_index_0]
    col.binAt = off + col.at
    local _list_1 = tbl.rows
    for _index_1 = 1, #_list_1 do
      local row = _list_1[_index_1]
      row[col.binAt] = col:slot(row[col.at])
    end
  end
  tbl.kodeAt, tbl.kodes, tbl.nk = off + tbl.klass.at, { }, 0
  local seen = { }
  local _list_1 = tbl.rows
  for _index_0 = 1, #_list_1 do
    local row = _list_1[_index_0]
    local v = row[tbl.klass.at]
    if not seen[v] then
      tbl.nk = tbl.nk + 1
      seen[v] = tbl.nk
      tbl.kodes[tbl.nk] = v
    end
    row[tbl.kodeAt] = seen[v]
  end
  return nil
end

-- Count `rows` into (bin x klass); report the occupied span and how
-- many rows landed.  The span keeps a four-row leaf from sweeping
-- fifty-one bins.
tally = function(col, rows, kat, nk, nb, lo, up, nn, k, b, at)
  for k = 1, nb * nk do
    Hist[k] = 0
  end
  lo, up, nn = nb + 1, 0, 0
  at = col.binAt
  for _, row in order(rows) do
    b = row[at]
    if b then
      local _update_0 = (b - 1) * nk + row[kat]
      Hist[_update_0] = Hist[_update_0] + 1
      lo, up, nn = min(lo, b), max(up, b), nn + 1
    end
  end
  return lo, up, nn
end

-- NUMERIC: walk left to right, moving each bin's counts from `that`
-- side to `this` one, offering the cut that leaves behind.  `cl` is carried
-- rather than rebuilt; old term off then new term on, in that order,
-- because float addition is not associative and `(cl-a)+z` differs
-- from `cl+(z-a)` by enough to flip a near-tie.
NUM.sweep = function(self, nk, lo, up, nn, out, on, tcl, ocl, b, i, c, a, z)
  on, nn, tcl, ocl = nn, 0, 0, 0
  for i = 1, nk do
    ThisC[i], ThatC[i] = 0, 0
    for b = lo, up do
      ThatC[i] = ThatC[i] + Hist[(b - 1) * nk + i]
    end
    ocl = ocl + clog(ThatC[i])
  end
  for b = lo, up - 1 do
    for i = 1, nk do
      c = Hist[(b - 1) * nk + i]
      if c == 0 then
        goto _continue_1
      end
      a, z = clog(ThisC[i]), clog(ThisC[i] + c)
      ThisC[i], tcl = ThisC[i] + c, tcl - a + z
      a, z = clog(ThatC[i]), clog(ThatC[i] - c)
      ThatC[i], ocl = ThatC[i] - c, ocl - a + z
      nn, on = nn + c, on - c
      ::_continue_1::
    end
    if nn < the.leaf or on < the.leaf then
      goto _continue_0
    end
    out(sc(nn, tcl, on, ocl), self:edge(b))
    ::_continue_0::
  end
  return nil
end

-- SYMBOLIC: a cut is `x == v`, not `x <= v`, so `this` is one bin on
-- its own and `that` is everything else -- no carrying, and the bins
-- need no order between them.
SYM.sweep = function(self, nk, lo, up, nn, out, b, i, c, d, tn, on, tcl, ocl)
  for i = 1, nk do
    ThatC[i] = 0
    for b = lo, up do
      ThatC[i] = ThatC[i] + Hist[(b - 1) * nk + i]
    end
  end
  for b = lo, up do
    tn, on, tcl, ocl = 0, 0, 0, 0
    for i = 1, nk do
      c = Hist[(b - 1) * nk + i]
      d = ThatC[i] - c
      tn, tcl = tn + c, tcl + clog(c)
      on, ocl = on + d, ocl + clog(d)
    end
    if tn < the.leaf or on < the.leaf then
      goto _continue_0
    end
    out(sc(tn, tcl, on, ocl), self:edge(b))
    ::_continue_0::
  end
  return nil
end

-- One column, counted and swept.  The only thing the two kinds still
-- disagree about is what a cut MEANS, so that is the one thing the
-- column is asked: `slots`, `slot`, `edge` and `sweep` all dispatch on
-- it, and nothing here tests which kind it is.
--
-- The counting stays a plain function.  `NUM` and `SYM` are two
-- metatables with no parent -- `Col` picks between them, it is not a
-- base class -- so a shared prologue has nowhere polymorphic to live,
-- and giving it the name `hist` on both would mean copying it twice.
hist = function(col, rows, kat, nk, out, nb, lo, up, nn)
  nb = col:slots()
  if not (nb and nb > 1) then
    return
  end
  lo, up, nn = tally(col, rows, kat, nk, nb)
  if nn < 2 * the.leaf or lo >= up then
    return
  end
  return col:sweep(nk, lo, up, nn, out)
end

-- The cut of `rows` that leaves the least klass entropy, found by
-- counting.  `tab` grows trees over klasses only -- regression is
-- `Rmeans`' job -- so every target is a `Sym` and both column kinds
-- reduce to the same histogram: bin the column, count (bin x klass),
-- sweep the boundaries.  Nothing is sorted and nothing is
-- accumulated into a `Sym`, which is where the time used to go.
TAB.cut = function(self, rows, cols)
  local col1
  local bs, bc, bv
  local offer
  offer = function(score, v)
    if bs == nil or score < bs then
      bs, bc, bv = score, col1, v
    end
  end
  binRows(self)
  for _, col in order(pick(self.x, cols)) do
    col1 = col
    hist(col, rows, self.kodeAt, self.nk, offer)
  end
  return bs and {
    col = bc,
    v = bv
  }
end

-- ---- rmeans ---------------------------------------------------------
Rmeans = function(tbl, rows, y)
  local i = new(RMEANS, {
    all = Num(),
    has = { }
  })
  local sub = tbl:clone(rows)
  i.cols = sub.x
  adds(sub.rows, i.all, y)
  for _, col in order(sub.x) do
    local bins = { }
    for _, row in order(sub.rows) do
      local b = col:bin(row[col.at])
      bins[b] = bins[b] or Num()
      bins[b]:add(y(row))
    end
    local on
    on = function(v)
      return v.n / i.all.n * (v:div() ^ 2)
    end
    local w = (i.all:div() ^ 2) - sum(bins, on)
    i.has[col.at] = {
      bins = bins,
      w = max(0, w)
    }
  end
  return i
end

RMEANS.like = function(self, col, row)
  local it = self.has[col.at]
  local v = it and it.bins[col:bin(row[col.at])]
  if v and it.w > 0 then
    return (v.n * v.mu + the.m * self.all.mu) / (v.n + the.m), it.w
  end
  return nil
end

RMEANS.guess = function(self, row)
  local s, w = 0, 0
  for _, col in order(self.cols) do
    local g, wt = self:like(col, row)
    if g then
      s, w = s + wt * g, w + wt
    end
  end
  return w > 0 and s / w or self.all.mu
end

-- ---- bayes ----------------------------------------------------------
Nb = function(tbl, rows)
  local i = new(NB, {
    tbl = tbl,
    subs = { },
    n = #rows,
    nKlass = 0
  })
  for _, row in order(rows) do
    local v = row[tbl.klass.at]
    if not i.subs[v] then
      i.subs[v], i.nKlass = tbl:clone(), i.nKlass + 1
    end
    i.subs[v]:add(row)
  end
  return i
end

-- `cols` is what the likelihood runs over, so a caller holding a
-- column subset -- an ensemble member drawn on its own subspace --
-- can ask this NB about just those, with no second NB built for it.
-- Default `sub.x` is every x column, which is what every existing
-- caller meant.  The global column is reached by `@tbl.cols[col1.at]`
-- rather than by position in `x`, so a subset LIST works and keeps
-- one iteration order; indexing `@tbl.x[at]` would have needed the
-- subset to stay sparse and be walked by `pairs`.
NB.like = function(self, sub, row, cols)
  if cols == nil then
    cols = sub.x
  end
  local on
  on = function(col1, at)
    local col, v = self.tbl.cols[col1.at], row[col1.at]
    if v == "?" then
      return 0
    end
    local seen = (col1.has[v] or 0) + the.m
    local all = col1.n + the.m * col:nVals()
    return log(seen / all)
  end
  local prior = log((#sub.rows + the.m) / (self.n + the.m * self.nKlass))
  return prior + sum(cols, on)
end

-- `pairs` has no order, so a klass tie used to fall whichever way
-- the hash happened to lie.  Sort the keys once and every tie after
-- goes to the same klass in lua, yue and python alike.
NB.klasses = function(self)
  local ks = { }
  for k in pairs(self.subs) do
    ks[#ks + 1] = k
  end
  return sort(ks, function(a, b)
    return tostring(a) < tostring(b)
  end)
end

NB.guess = function(self, row)
  local b, bk, v
  b = -math.huge
  for _, k in order(self:klasses()) do
    v = self:like(self.subs[k], row)
    if v > b then
      b, bk = v, k
    end
  end
  return bk
end

-- p(klass | `row`), so an ensemble can average how sure it is -- and
-- so an auc has a score to rank by.  `like` returns a LOG likelihood,
-- so the top one comes off before `exp`, which would otherwise
-- underflow to zero for every klass at once.
NB.posts = function(self, row)
  local hi, z
  local ks, t = self:klasses(), { }
  hi = -math.huge
  for _, k in order(ks) do
    t[k] = self:like(self.subs[k], row)
    hi = max(hi, t[k])
  end
  z = 0
  for _, k in order(ks) do
    t[k] = exp(t[k] - hi)
    z = z + t[k]
  end
  local u = { }
  for _, k in order(ks) do
    u[k] = t[k] / z
  end
  return u
end

-- ---- tree -----------------------------------------------------------
-- One node over `rows`, summarized, then grown.  `cols` is how many
-- x columns a split may look at (0 = all of them); it rides down the
-- tree so every node redraws its own few.
-- `tab` grows trees over a KLASS only; regression is `Rmeans`' job,
-- and a tree whose target is a distance has no entropy to count.
Tree = function(tbl, rows, lvl, cols)
  rows = rows or tbl.rows
  local node = new(TREE, {
    tbl = tbl,
    rows = rows,
    lvl = lvl or 1,
    cols = cols or 0,
    n = #rows,
    txt = ""
  })
  return node:sum():grow()
end

-- What this node answers with: `@all` (its rows' klasses, summarized)
-- and `@mid` (their majority).  Both are wanted by a leaf that has to
-- vote, so both survive the search caching klass codes on the rows.
TREE.sum = function(self, at)
  self.all, at = Sym(), self.tbl.klass.at
  for _, row in order(self.rows) do
    self.all:add(row[at])
  end
  self.mid = self.all:mid()
  return self
end

-- `@`, with two kids under it when a cut pays: deep enough to bother,
-- big enough to split, and both sides big enough to keep.  Each kid
-- is a `Tree`, which grows in turn -- so the pair recurse together.
TREE.grow = function(self)
  local cut = self.n >= 2 * the.leaf and self.lvl < the.depth and self:cut()
  if cut then
    local a, b = { }, { }
    for _, row in order(self.rows) do
      local t = cut.col:holds(row[cut.col.at], cut.v) and a or b
      t[#t + 1] = row
    end
    if #a >= the.leaf and #b >= the.leaf then
      self.at = cut
      self.left = Tree(self.tbl, a, self.lvl + 1, self.cols)
      self.right = Tree(self.tbl, b, self.lvl + 1, self.cols)
      local op = cut.col.it == SYM and {
        "==",
        "~="
      } or {
        "<=",
        ">"
      }
      self.left.txt = cut.col.txt .. " " .. op[1] .. " " .. o(cut.v)
      self.right.txt = cut.col.txt .. " " .. op[2] .. " " .. o(cut.v)
    end
  end
  return self
end

TREE.cut = function(self)
  return self.tbl:cut(self.rows, self.cols)
end

-- A TAB of just `@rows`, so `ycols` and `dict` can report what this
-- node's y columns look like.  Cloning is the costliest thing a node
-- can do and only reporting needs it -- `cut` reads `col.at` and the
-- rows it is handed, never a column's running stats -- so this waits
-- until something asks.  A 30-tree forest never asks.
TREE.sub = function(self)
  self.subbed = self.subbed or self.tbl:clone(self.rows)
  return self.subbed
end

-- ---- asking ---------------------------------------------------------
TREE.pick = function(self, row)
  if not self.at then
    return self
  end
  local c = self.at
  return (c.col:holds(row[c.col.at], c.v) and self.left or self.right):pick(row)
end

TREE.ycols = function(self, f)
  local t, node = { }, self:sub()
  for k, col in order(node.y) do
    t[k] = ("%" .. max(10, #col.txt + 2) .. "s"):format(f(col))
  end
  return table.concat(t)
end

TREE.walk = function(self)
  local todo = {
    self
  }
  return function()
    local n = table.remove(todo)
    if not n then
      return
    end
    if n.at then
      todo[#todo + 1] = n.right
      todo[#todo + 1] = n.left
    end
    return n
  end
end

TREE.show = function(self)
  local cell
  cell = function(col)
    return col.it == NUM and o(col.mu) or best(col.has, same)
  end
  local t, ends = { }, { }
  for n in self:walk() do
    if not n.at then
      t[#t + 1] = n
    end
  end
  sort(t, "mid")
  ends[t[#t]] = " \226\156\151 "
  ends[t[1]] = " \226\156\147 "
  print(("%-26s %5s %6s   %s"):format("", "n", "mid", self:ycols(function(col)
    return col.txt
  end)))
  for n in self:walk() do
    print(("%-26s %5d %6s%s%s"):format(("|  "):rep(max(0, n.lvl - 2)) .. n.txt, n.n, o(n.mid), ends[n] or "   ", n:ycols(cell)))
  end
  print("")
  return nil
end

-- Return `@` as nested tables: this node's n, mid, split and y-column
-- centers, then its two kids under `left` and `right`.  So `logfmt`
-- prints the whole tree as a record a later run can be diffed against.
TREE.dict = function(self)
  local t, node = {
    n = self.n,
    mid = self.mid
  }, self:sub()
  if self.txt ~= "" then
    t.txt = self.txt
  end
  for _, col in order(node.y) do
    t[col.txt] = col.it == NUM and col.mu or best(col.has, same)
  end
  if self.at then
    t.left, t.right = self.left:dict(), self.right:dict()
  end
  return t
end

-- ---- predicting -----------------------------------------------------
TREE.nb = function(self)
  self.model = self.model or Nb(self:sub(), self.rows)
  return self.model
end

TREE.posts = function(self, row)
  local n, t = self:pick(row), { }
  for k, m in pairs(n.all.has) do
    t[k] = m / n.all.n
  end
  return t
end

-- ---- forest ---------------------------------------------------------
-- `rounds` deep trees, each on its own bootstrap of `rows`, each node
-- splitting on sqrt(#x) columns it draws itself.  Breiman's random
-- forest, so: rows sampled once per tree, attributes resampled at
-- every split.
Forest = function(tbl, rows, rounds)
  rows = rows or tbl.rows
  local c = max(1, floor(sqrt(#tbl.x)))
  local i = new(FOREST, {
    all = { },
    tbl = tbl
  })
  for k = 1, rounds or the.rounds do
    i.all[k] = Tree(tbl, some(rows, #rows), 1, c)
  end
  return i
end

-- A HARD vote: each tree offers one label -- its leaf's majority --
-- and `ks` is the order the labels first arrived in.  That order is
-- the tie-break: two labels on 15 votes each are settled by which
-- tree spoke first, which is the same in any port, where `pairs`
-- order is not.
FOREST.votes = function(self, row)
  local t, ks = { }, { }
  for _, m in order(self.all) do
    local k = m:pick(row).mid
    if k ~= nil then
      if t[k] == nil then
        ks[#ks + 1] = k
      end
      t[k] = (t[k] or 0) + 1
    end
  end
  return t, ks
end

-- The tally, normalized, so this still reads as p(klass | `row`) and
-- anything wanting a score to rank by (an auc) still has one.
FOREST.posts = function(self, row)
  local t, ks = self:votes(row)
  local z = 0
  for _, k in order(ks) do
    z = z + t[k]
  end
  local _tbl_0 = { }
  for _, k in order(ks) do
    _tbl_0[k] = t[k] / max(z, 1)
  end
  return _tbl_0
end

FOREST.guess = function(self, row)
  local t, ks = self:votes(row)
  local bk
  local b = -1
  for _, k in order(ks) do
    if t[k] > b then
      b, bk = t[k], k
    end
  end
  return bk
end

-- ---- misc -----------------------------------------------------------
new = function(meta, i)
  meta.__index, meta.it, meta.__tostring = meta, meta, o
  return setmetatable(i, meta)
end

cli = function()
  for _, s in order(arg) do
    local k, v = s:match("^(%a%w*)=(.*)$")
    if k then
      the[k] = values(v)[1]
    elseif eg[s] or slow[s] then
      (eg[s] or slow[s])()
    else
      the.file = s
    end
  end
  return the
end

-- Restart the generator at `n`, or back at `the.seed`.  The setting
-- and the state are two things: `the.seed` says where a run began,
-- `rng` is where it has got to, so a header can still name the seed.
seed = function(n)
  rng = n or the.seed
  return nil
end

rint = function(n)
  rng = (16807 * (rng or the.seed)) % 2147483647
  return 1 + floor(n * rng / 2147483647)
end

shuffle = function(t)
  for k = #t, 2, -1 do
    local j = rint(k)
    t[k], t[j] = t[j], t[k]
  end
  return t
end

-- `n` of `t`, drawn WITH replacement: one bootstrap sample.  At
-- n=#t about 63% of `t` turns up at least once, so the rest is that
-- member's out-of-bag rows -- free held-out data, no extra split.
some = function(t, n)
  local u = { }
  for k = 1, n or #t do
    u[k] = t[rint(#t)]
  end
  return u
end

-- `n` of `t`, no replacement; all of `t` when `n` is 0 or too big.
-- Shuffles a copy on tab's own `rint`, so a draw is a seed.
-- A forest redraws its columns at EVERY node, so this used to build
-- two arrays a node for a list it throws away.  Pooled: the draw
-- order is untouched, so `rint` is called exactly as often and in
-- the same sequence, and the trees come out the same.
Drawn = { }
pick = function(t, n)
  if not n or n == 0 or n >= #t then
    return t
  end
  for k = 1, #t do
    Drawn[k] = t[k]
  end
  for k = #Drawn, #t + 1, -1 do
    Drawn[k] = nil
  end
  shuffle(Drawn)
  for k = #Drawn, n + 1, -1 do
    Drawn[k] = nil
  end
  return Drawn
end

map = function(t, on)
  local u = { }
  for k, v in ipairs(t) do
    u[#u + 1] = on(v, k)
  end
  return u
end

sum = function(t, on)
  local n = 0
  for k, v in pairs(t) do
    n = n + on(v, k)
  end
  return n
end

adds = function(src, it, on)
  it = it or Num()
  on = on or same
  for _, x in order(src) do
    it:add(on(x))
  end
  return it
end

best = function(t, on)
  local n, m, u
  for k, v in pairs(t) do
    m = on(v, k)
    if not n or m > n then
      n, u = m, k
    end
  end
  return u, n
end

same = function(x)
  return x
end
lt = function(a, b)
  return a < b
end

sort = function(t, on)
  if on and type(on) ~= "function" then
    local k = on
    on = function(a, b)
      return a[k] < b[k]
    end
  end
  table.sort(t, on)
  return t
end

order = function(t, on)
  if type(t) == "string" then
    t = csv(t)
  end
  if not on then
    return ipairs(t)
  end
  return ipairs(sort(map(t, same), on))
end

o = function(x)
  if type(x) ~= "table" then
    if type(x) ~= "number" then
      return tostring(x)
    end
    return tostring(x == floor(x) and floor(x) or the.fmt:format(x))
  end
  local u = { }
  if #x > 0 then
    for _, v in ipairs(x) do
      u[#u + 1] = o(v)
    end
  else
    for k, v in pairs(x) do
      if k ~= "it" and type(v) ~= "function" then
        u[#u + 1] = o(k) .. "=" .. o(v)
      end
    end
  end
  return "{" .. table.concat((#x > 0 and u or sort(u, lt)), " ") .. "}"
end

print = function(...)
  local out = { }
  for j = 1, select("#", ...) do
    out[j] = o((select(j, ...)))
  end
  io.write(table.concat(out, "\t"), "\n")
  return nil
end

fmt = function(s, ...)
  return s:format(...)
end

-- Return `d:dict` as "k=v k=v" lines, keys sorted.  Atoms pack onto
-- one line; a table value gets its key, then its own lines, indented
-- one more stop.  So a nested dict prints as deep as it really is.
logfmt = function(d, indent)
  local pad = ("  "):rep(indent or 0)
  local u, flat, out = { }, { }, { }
  for k in pairs(d) do
    u[#u + 1] = k
  end
  sort(u)
  for _, k in order(u) do
    if type(d[k]) ~= "table" then
      flat[#flat + 1] = k .. "=" .. o(d[k])
    end
  end
  if #flat > 0 then
    out[1] = pad .. table.concat(flat, " ")
  end
  for _, k in order(u) do
    if type(d[k]) == "table" then
      out[#out + 1] = pad .. k
      out[#out + 1] = logfmt(d[k], (indent or 0) + 1)
    end
  end
  return table.concat(out, "\n")
end

-- Say what this run was: when it ran, which version ran it, what it
-- was asked, and every setting in play.  An eg prints this above its
-- results, so a result read a year later knows where it came from.
about = function()
  print(":config")
  local cmd = (arg and arg[0] or "?") .. (arg and #arg > 0 and " " .. table.concat(arg, " ") or "")
  print(logfmt({
    date = os.date("%Y-%m-%d %H:%M:%S"),
    version = the.version,
    cmd = cmd
  }))
  print(logfmt(the))
  return nil
end

-- ---- tests ----------------------------------------------------------
-- Demos double as tests: each prints a little, asserts golden values.
-- Port tab to another language, pass these, and the port agrees with
-- tab.lua to 1e-6.  `eg` run under --all; `slow` only when named.
eg, slow = { }, { }

near = function(a, b)
  return abs(a - b) < 1e-6
end

ok = function(got, want)
  assert((got == want or (type(got) == "number" and type(want) == "number" and near(got, want))), o(got) .. " ~= " .. o(want))
  return got
end

run = function(k)
  print(":" .. k:gsub("^%-+", ""))
  seed();
  (eg[k] or slow[k])()
  return nil
end

eg["-h"] = function()
  print(help)
  return nil
end

eg["--all"] = function()
  local worst = 0
  local who
  local keys = { }
  for k in pairs(eg) do
    if not (" -h --all "):find(" " .. k .. " ", 1, true) then
      keys[#keys + 1] = k
    end
  end
  for _, k in order(keys, lt) do
    local t0 = os.clock()
    run(k)
    local ms = (os.clock() - t0) * 1000
    if ms > worst then
      worst, who = ms, k
    end
  end
  print(fmt("PASS %s tests, worst %s at %.1fms", #keys, who, worst))
  return nil
end

slow["--secs"] = function()
  local file = the.file or the.train
  local tbl, tot = Tab(file), 0
  for r = 1, the.reps do
    seed(the.seed + r)
    local tr, te = tbl:split()
    local sub = tbl:clone(tr)
    local y
    y = function(row)
      return sub:ydist(row)
    end
    local lim = the.budget - the.check
    local t0 = os.clock()
    local few = { }
    for j = 1, (#tr < lim and #tr or lim) do
      few[j] = tr[j]
    end
    local model = Rmeans(tbl, few, y)
    for _, row in order(te) do
      model:guess(row)
    end
    tot = tot + (os.clock() - t0)
  end
  print(fmt("%s rows=%6d secs=%.4f", file:match("([^/]+)%.csv$"), #tbl.rows, tot / the.reps))
  return nil
end

eg["--values"] = function()
  local t = values(" 4.2, x,3")
  print(logfmt({
    got = o(t)
  }))
  ok(t[1], 4.2)
  ok(t[2], "x")
  ok(t[3], 3)
  return nil
end

eg["--csv"] = function()
  local t = csv(the.train)
  print(logfmt({
    rows = #t,
    cells = #t[1]
  }))
  ok(#t, 399)
  ok(#t[1], 8)
  ok(t[1][1], "Clndrs")
  return nil
end

eg["--num"] = function()
  local n = adds({
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10
  })
  print(logfmt({
    mu = n:mid(),
    sd = n:div()
  }))
  ok(n:div(), 3.0276503541)
  return nil
end

eg["--sym"] = function()
  local s = adds({
    "a",
    "a",
    "b",
    "c",
    "c",
    "c"
  }, Sym())
  print(logfmt({
    mode = s:mid(),
    ent = s:div()
  }))
  ok(s:div(), 1.4591479170)
  return nil
end

eg["--tab"] = function()
  local t = Tab(the.train)
  print(logfmt({
    rows = #t.rows,
    x = #t.x,
    y = #t.y
  }))
  ok(#t.rows, 398)
  ok(#t.x, 4)
  ok(#t.y, 3)
  return nil
end

eg["--mid"] = function()
  local t = Tab(the.train)
  print(logfmt(t:mid(t.y)))
  ok(t:mid(t.y)["Acc+"], 15.5680904523)
  return nil
end

eg["--ydist"] = function()
  local t = Tab(the.train)
  print(logfmt({
    guzzler = t:ydist(t.rows[1]),
    honda = t:ydist(t.rows[398])
  }))
  ok(t:ydist(t.rows[1]), 0.7863215821)
  ok(t:ydist(t.rows[398]), 0.1410148526)
  return nil
end

eg["--split"] = function()
  local t = Tab(the.train)
  local tr, te = t:split()
  print(logfmt({
    train = #tr,
    test = #te
  }))
  ok(#tr, 318)
  ok(#te, 80)
  ok(table.concat(tr[1], ","), "6,145,76,81,2,3160,19.6,30")
  ok(t.rows[1][1], 8)
  return nil
end

eg["--rmeans"] = function()
  local t, few = Tab(the.train), { }
  local y
  y = function(row)
    return t:ydist(row)
  end
  for k = 1, 45 do
    few[k] = t.rows[k]
  end
  local m = Rmeans(t, few, y)
  print(logfmt({
    mu = m.all.mu,
    guess = m:guess(t.rows[1])
  }))
  ok(m.all.mu, 0.9009519530)
  ok(m:guess(t.rows[1]), 0.8530303902)
  return nil
end

eg["--nb"] = function()
  local t = Tab({
    {
      "Age",
      "job",
      "klass!"
    },
    {
      20,
      "low",
      "no"
    },
    {
      22,
      "low",
      "no"
    },
    {
      25,
      "low",
      "no"
    },
    {
      30,
      "med",
      "no"
    },
    {
      60,
      "hi",
      "yes"
    },
    {
      62,
      "hi",
      "yes"
    },
    {
      65,
      "med",
      "yes"
    },
    {
      70,
      "hi",
      "yes"
    }
  })
  local b = t:clone(t.rows, "bin")
  local i = Nb(b, b.rows)
  print(logfmt({
    young = i:guess(b.rows[1]),
    old = i:guess(b.rows[8])
  }))
  ok(i:guess(b.rows[1]), "no")
  ok(i:guess(b.rows[8]), "yes")
  return nil
end

eg["--logfmt"] = function()
  local s = logfmt({
    seed = 1,
    go = "nb",
    sub = {
      b = 2,
      a = 1
    }
  })
  print(s)
  ok(s, "go=nb seed=1\nsub\n  a=1 b=2")
  return nil
end

-- The module's surface at the foot of this file is written out by
-- hand, which reads well but drifts: add a function, forget the
-- list, and `require "tab"` quietly lacks it.  So check it, from the
-- source text -- textual on purpose, because the table does not
-- exist yet while this file is still running.  Every top-level name
-- must be exported or named below as deliberately private.  `Hist`
-- and `Drawn` are scratch, `main` is the entry test, and the rest
-- are tree internals that nothing outside this file calls.
eg["--api"] = function()
  local priv
  do
    local _tbl_0 = { }
    for w in (" Drawn Hist ThatC ThisC binRows clog " .. "ent hist main sc tally "):gmatch("%S+") do
      _tbl_0[w] = true
    end
    priv = _tbl_0
  end
  local src = debug.getinfo(1, "S").source:gsub("^@", "")
  src = src:gsub("%.lua$", ".yue")
  local defs, want, tail, str = { }, { }, false, false
  for line in io.lines(src) do
    if line:find("^setmetatable") then
      tail = true
    end
    if tail then
      for w in line:gmatch("[:,]%s*(%a[%w_]*)") do
        want[w] = true
      end
    elseif str then
      if line:find("%]%]") then
        str = false
      end
    else
      local lhs = line:match("^([^=]-)%s*=[^=]")
      if lhs and lhs:find("^[%a_]") and not lhs:find("[^%w_,%s]") then
        for w in lhs:gmatch("[%a_][%w_]*") do
          defs[w] = true
        end
      end
      if line:find("%[%[") and not line:find("%]%]") then
        str = true
      end
    end
  end
  local gone
  do
    local _accum_0 = { }
    local _len_0 = 1
    for k in pairs(defs) do
      if not (want[k] or priv[k]) then
        _accum_0[_len_0] = k
        _len_0 = _len_0 + 1
      end
    end
    gone = _accum_0
  end
  local dead
  do
    local _accum_0 = { }
    local _len_0 = 1
    for k in pairs(want) do
      if not defs[k] then
        _accum_0[_len_0] = k
        _len_0 = _len_0 + 1
      end
    end
    dead = _accum_0
  end
  print(fmt("%s exported, %s private", sum(want, function()
    return 1
  end), sum(priv, function()
    return 1
  end)))
  ok(table.concat(sort(gone, lt), " "), "")
  ok(table.concat(sort(dead, lt), " "), "")
  return nil
end

halves = function()
  local tbl = Tab(the.file)
  local tr, te = tbl:split()
  tr, te = tbl:clone(tr), tbl:clone(te)
  local y
  y = function(row)
    return tr:ydist(row)
  end
  return tr, te, y
end

-- ---- start ----------------------------------------------------------
for k, v in help:gmatch("\n%s+(%a+)=(%S+)") do
  the[k] = values(v)[1]
end
the.file = the.train

main = (arg and arg[0]) or ""
if main:find("tab%.yue$") or main:find("tab%.lua$") then
  if #arg == 0 then
    eg["-h"]()
  else
    cli()
  end
end

-- Lua's `_ENV` trick is gone.  This is what replaces it: one table,
-- written out, so the module's surface is a list you can read rather
-- than "whatever the chunk happened to assign".  `__index: _G` keeps
-- tab-eg's `local _ENV = tab` working -- math, io and table still
-- resolve through it.  `rng` is deliberately absent: it is state, not
-- API.
return setmetatable({
  the = the,
  help = help,
  eg = eg,
  slow = slow,
  floor = floor,
  exp = exp,
  sqrt = sqrt,
  log = log,
  abs = abs,
  min = min,
  max = max,
  TAB = TAB,
  NUM = NUM,
  SYM = SYM,
  RMEANS = RMEANS,
  NB = NB,
  TREE = TREE,
  FOREST = FOREST,
  values = values,
  csv = csv,
  Col = Col,
  Sym = Sym,
  Num = Num,
  Tab = Tab,
  Rmeans = Rmeans,
  Nb = Nb,
  Tree = Tree,
  Forest = Forest,
  new = new,
  cli = cli,
  seed = seed,
  rint = rint,
  shuffle = shuffle,
  some = some,
  pick = pick,
  map = map,
  sum = sum,
  adds = adds,
  best = best,
  same = same,
  lt = lt,
  sort = sort,
  order = order,
  o = o,
  print = print,
  fmt = fmt,
  logfmt = logfmt,
  about = about,
  near = near,
  ok = ok,
  run = run,
  halves = halves
}, {
  __index = _G
})
