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
  version=0.5.0    version number
  bins=7           numeric columns get this many bins
  budge=50         a fast test over this many ms belongs in slow
  budget=50        labels, all in
  check=5          of those, saved for the test rows
  fmt=%.2f         how a fraction is printed
  m=2              m-estimate: prior weight for a thin bin
  p=2              minkowski coefficient
  reps=3           repeats, when something is timed
  seed=1234567891  random number seed
  file=~/gits/moot/optimize/misc/auto93.csv

actions:
   -h              print help
   --all           every fast action (--num, --split ... run one)
   --secs          slow: time rmeans, over `reps` repeats

Any flag above can lead an action, so `reps=9 --secs` times ni:wne.]]

floor, exp, sqrt, log = math.floor, math.exp, math.sqrt, math.log
abs, min, max = math.abs, math.min, math.max

TAB,NUM,SYM,RMEANS,NB,BAG,SAME = {},{},{},{},{},{},{}

-- value = str | num 
-- row = list[row]
-- rows = list[rows]
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
-- NUM and SYM share one protocol: add, div, norm, bin.  Each verb's
-- two faces sit together below.  nVals is SYM's alone.

function Col(txt,at) 
   return (txt:find"^%u" and Num or Sym)(txt, at) end

function Sym(txt,at) --> SYM; a SYM for `txt:str` at `at:num`: a-z names,
  return new(SYM, {txt = txt or "S", at = at or 0, n = 0, has = {}}) end

function Num(txt,at) --> NUM; a NUM for `txt:str` at `at:num`: A-Z num, !+-
  return new(NUM, {txt = txt or "N", at = at or 0, n = 0, mu = 0, m2 = 0,
                   w = (txt or ""):find"%-$" and 0 or 1}) end

function nums(lst,fn,    i) --> NUM; one NUM summarizing `fn(x)` over
  fn = fn or same
  i=Num(); for _,x in order(lst) do i:add(fn(x)) end; return i end

function SYM.add(i,v,inc) --> value; add one more `v:value` to `i`'s counts.
  if v == "?" then return v end
  inc = inc or 1
  i.n = i.n + inc
  i.has[v] = (i.has[v] or 0) + inc
  if i.has[v] <= 0 then i.has[v] = nil end
  return v end

function NUM.add(i,v,inc,    d) --> value; add `v:value` to `i`, returning
  if v == "?" then return v end
  inc = inc or 1
  i.n = i.n + inc
  if i.n <= 0 then i.n, i.mu, i.m2 = 0, 0, 0; return v end
  d    = v - i.mu
  i.mu = i.mu + inc * d / i.n
  i.m2 = i.m2 + inc * d * (v - i.mu)
  return v end

function SYM.__sub(i,j,    k,m) --> SYM; what is left of `i` once `j` is
  k = new(SYM, {txt = i.txt, at = i.at, n = i.n - j.n, has = {}})
  for v, n in pairs(i.has) do
    m = n - (j.has[v] or 0)
    if m > 0 then k.has[v] = m end end
  return k end

function NUM.__sub(i,j,    n,d) --> NUM; what is left of `i` once `j` is
  n = i.n - j.n
  if n < 1 then return Num(i.txt, i.at) end
  d = j.mu - i.mu
  return new(NUM, {txt = i.txt, at = i.at, w = i.w, n = n,
                   mu = (i.n*i.mu - j.n*j.mu) / n,
                   m2 = max(0, i.m2 - j.m2 - d*d*i.n*j.n/n)}) end

function SYM.div(i,    fn) --> num; `i`'s entropy.
  fn = function(n) return -n/i.n * log(n/i.n) end
  return sum(i.has, fn) / log(2) end

function NUM.div(i) --> num; `i`'s standard deviation.
  return i.n < 2 and 0 or sqrt(max(i.m2, 0) / (i.n - 1)) end

function SYM.norm(i,v) return v end --> value; a sym is its own norm

function NUM.norm(i,v,    z) --> value; `v:value` on a logistic cdf, clipped
  if v == "?" then return v end
  z = (v - i.mu) / (i:div() + 1e-32)
  z = z > 3 and 3 or (z < -3 and -3 or z)
  return 1 / (1 + exp(-1.7 * z)) end

function SYM.holds(i,x,v) return x == "?" or x == v end --> bool

-- Return true when cell `x` is on `v`'s side of a cut.  An unknown
-- says yes to everything, so a cut never loses a row.
function NUM.holds(i,x,v) return x == "?" or x <= v end --> bool

function SYM.bin(i,v) return v end --> value ; a sym is its own bin

function NUM.bin(i,v,    b) --> value; `v:value`'s bin, 1..`the.bins`.
  if v == "?" then return v end
  b = 1 + floor(the.bins * i:norm(v))
  return b > the.bins and the.bins or b end

function SYM.nVals(i,    fn) --> int; how many values `i` has seen, at
  i.kinds = i.kinds or max(2, sum(i.has, function() return 1 end))
  return i.kinds end

-- ---- tables ----------------------------------------------------------
function Tab(src,    i) --> TAB; a TAB from `src`: a file name, or names
  i = new(TAB, {rows = {}})
  for _, row in order(type(src) == "string" and csv(src) or src) do
    i:addRow(row) end
  return i end

function TAB.head(i,names,    col) --> nil; read `names:row` as `i`'s
  i.names, i.cols, i.x, i.y = names, {}, {}, {}
  for at, txt in order(names) do
    col = Col(txt, at)
    i.cols[#i.cols + 1] = col
    if     txt:find"X$"     then                 -- summarized, skipped
    elseif txt:find"[-+!]$" then i.y[#i.y + 1] = col
      if txt:find"!$" then i.klass = col end  -- last ! is the klass
    else i.x[#i.x + 1] = col end end end

function TAB.addRow(i,row) --> row; add `row` to `i`.  The first row read
  if not i.cols then return i:head(row) end
  i.rows[#i.rows + 1] = row
  for _, col in order(i.cols) do col:add(row[col.at]) end
  return row end

function TAB.clone(i,rows,how,    out) --> TAB; `rows` in a fresh TAB
  out = {how and map(i.cols, function(col) return col.txt:lower() end)
             or i.names}
  for _, row in order(rows or {}) do
    out[#out + 1] = not how and row or map(i.cols,
      function(col) return col[how](col, row[col.at]) end) end
  return Tab(out) end

function TAB.ydist(i,row,    fn) --> num; `row`'s distance to heaven over
  fn = function(col)
          return abs(col:norm(row[col.at]) - col.w) ^ the.p end
  return (sum(i.y, fn) / #i.y) ^ (1 / the.p) end

function TAB.split(i,    rows,n,t,u1,u2) --> list; two lists, 80:20, of a
  rows   = shuffle(map(i.rows, same))    -- never i.rows itself
  n      = floor(.8 * #rows)
  u1, u2 = {}, {}; t = u1
  for j,row in order(rows) do if j>n then t = u2 end; t[#t+1] = row end
  return u1, u2 end

-- ---- rmeans ----------------------------------------------------------
function Rmeans(tbl,rows,y, --> RMEANS; per x column, its bins' y means
                sub,all,i,bins,b,w,fn)  -- and the variance they cut
  sub = tbl:clone(rows)
  all = nums(sub.rows, y)
  i   = new(RMEANS, {all = all, has = {}, cols = sub.x})
  for _, col in order(sub.x) do
    bins = {}
    for _, row in order(sub.rows) do
      b = col:bin(row[col.at])
      bins[b] = bins[b] or Num()
      bins[b]:add(y(row)) end
    fn = function(v) return v.n/all.n * v:div() ^ 2 end
    w  = all:div() ^ 2 - sum(bins, fn)
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
function Nb(tbl,rows,    i,col,v) --> NB; one sub-TAB per klass in `rows`
  col = tbl.klass
  i   = new(NB, {tbl = tbl, subs = {}, n = #rows, nKlass = 0})
  for _, row in order(rows) do
    v = row[col.at]
    if not i.subs[v] then
      i.subs[v], i.nKlass = tbl:clone(), i.nKlass + 1 end
    i.subs[v]:addRow(row) end
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

function NB.posts(i,row,    t,hi,z) --> dict; p(klass | `row`) for every
  t, hi = {}, nil
  for k, sub in pairs(i.subs) do
    t[k] = i:like(sub, row)
    if not hi or t[k] > hi then hi = t[k] end end
  z = 0
  for k, v in pairs(t) do t[k] = exp(v - hi); z = z + t[k] end
  for k, v in pairs(t) do t[k] = v / z end
  return t end

-- ---- misc ---------------------------------------------------------
function new(meta,i) --> inst; connect instance `i` to its class `meta`;
  meta.__index, meta.it, meta.__tostring = meta, meta, o
  return setmetatable(i, meta) end

function cli(    k,v) --> dict; update `the` from the command line: a flag,
  for _, s in order(arg) do        -- name=value, action, file
    k, v = s:match"^(%a%w*)=(.*)$"
    if     k               then the[k] = values(v)[1]
    elseif fast[s] or slow[s] then (fast[s] or slow[s])()
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

function map(t,fn,    u) --> list; `fn(v,k)` over `t`, in order, with nils
  u={}; for k, v in ipairs(t) do u[#u+1] = fn(v, k) end 
  return u end                                        

function sum(t,fn,    n) --> num; `fn(v,k)` over every item of `t`, added
  n=0; for k, v in pairs(t) do n = n + fn(v, k) end; return n end

function best(t,fn,    n,m,u) --> any; key of `t` with the biggest
  for k, v in pairs(t) do
    m = fn(v, k)
    if not n or m > n then n, u = m, k end end
  return u, n end

function same(x) return x end --> any

function lt(a,b) return a < b end --> bool

function sort(t,fn,    k) --> list; `t`, sorted in place, ascending.  `fn`
  if fn and type(fn) ~= "function" then
    k = fn; fn = function(a,b) return a[k] < b[k] end end
  table.sort(t, fn)
  return t end

function order(t,fn) --> fun; `ipairs(t)`, or, given `fn`, that of a sorted
  if not fn then return ipairs(t) end
  return ipairs(sort(map(t, same), fn)) end

function o(x,    u) --> str; `x` as text: a fraction through `the.fmt`, a
  if type(x) ~= "table" then              
    if type(x) ~= "number" then return tostring(x) end   
    return tostring(x == floor(x) and floor(x) or the.fmt:format(x)) end
  u = {}
  if #x>0 then for _, v in ipairs(x) do u[#u+1] = o(v) end
          else for k, v in pairs(x) do
                 if k ~= "it" and type(v) ~= "function" then
                   u[#u + 1] = o(k) .. "=" .. o(v) end end end
  return "{"..table.concat(#x > 0 and u or sort(u, lt)," ").."}" end

function print(...) --> nil; print the lot, tab separated, everything
  local out = {}
  for j = 1, select("#", ...) do out[j] = o((select(j, ...))) end
  io.write(table.concat(out, "\t"), "\n") end

function fmt(s,...) return s:format(...) end --> str; format short had

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
-- Each block of a run leads with `:name`, so nothing has to be
-- guessed from blank lines or indents.
function about(    t) --> nil
  print":config"                    -- a section, so a reader (and
  t = {date = os.date"%Y-%m-%d %H:%M:%S", version = the.version,
       cmd  = (arg and arg[0] or "?")
              .. (arg and #arg > 0
                  and " " .. table.concat(arg, " ") or "")}
  print(logfmt(t))
  print(logfmt(the)) end

-- ---- actions ----------------------------------------------------
fast, slow = {}, {}   -- fast: tests under --all.  slow: named only.
fast["-h"] = function() print(help) end

-- ---- start ------------------------------------------------------
for k, v in help:gmatch"\n%s+(%a+)=(%S+)" do the[k] = values(v)[1] end

if (arg and arg[0] or ""):find"tab%.lua$" then
  if #arg == 0 then fast["-h"]() else cli() end end

return _ENV
