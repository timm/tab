# Learn Lua in Y minutes, from tab.lua

<p align="center"><img src="../docs/logo.png" width="700"></p>

In the shape of [learnxinyminutes.com/lua](https://learnxinyminutes.com/lua/)
(by Tyler Neylon, CC BY-SA 3.0), but every example is real code from
`tab.lua` -- 563 lines that read csv files, discretize columns, run
naive Bayes and a range-means regressor, and test themselves.

Longer treatments: [lua101.md](../docs/lua101.md) for the language,
[luamore.md](../docs/luamore.md) for the idioms.

```lua
-- Two dashes start a one-line comment.

--[[
     Adding two [ and ] makes it a multi-line comment.
     tab.lua uses only the one-line kind, at most 75 columns wide,
     usually to the right of the code it explains.
--]]

----------------------------------------------------------------------
-- 1. Variables and flow control.
----------------------------------------------------------------------

num = 42    -- All numbers are doubles in Lua 5.1 and LuaJIT.
            -- 5.3+ has an integer subtype, but 1 == 1.0 either way.
            -- tab.lua never cares which it is running on.

-- Globals are the default. `local` is one word you must remember:
local min = require "tab"      -- tab-eg.lua, line 12

-- Multiple assignment, in parallel. tab.lua opens with it:
floor, exp, sqrt, log = math.floor, math.exp, math.sqrt, math.log
abs, min, max = math.abs, math.min, math.max

-- Eight empty tables, eight names, one line. These are the classes:
TAB,NUM,SYM,BINS,RMEANS,NB,BAG,SAME = {},{},{},{},{},{},{},{}

-- Parallel assignment means swapping needs no temporary, which is
-- the entire body of a Fisher-Yates shuffle:
function shuffle(t,    j)           -- in place, Fisher-Yates
  for k = #t, 2, -1 do j = rint(k); t[k], t[j] = t[j], t[k] end
  return t end

-- Undefined variables are nil, not an error. So missing arguments
-- give you default arguments for free:
function Num(txt,at)                -- no args: an anonymous num
  txt, at = txt or "N", at or 0

-- Strings are immutable. Concatenate with .. (not +):
cache = (os.getenv"HOME" or "~") .. "/tmp/cache"

-- Double brackets make a multi-line string, no escaping needed.
-- tab.lua keeps its help AND its default settings in one:
the,help = {}, [[
tab.lua: a good guess from a few dozen labels.

flags:
  bins=7           numeric columns get this many bins
  m=2              m-estimate: prior weight for a thin bin
  seed=1234567891  random number seed]]

-- Only nil and false are false. 0 is true. "" is true.
-- So `and`/`or` work as a ternary, and tab.lua uses them that way:
w = txt:find"%-$" and 0 or 1              -- a "-" name means minimize
z = z > 3 and 3 or (z < -3 and -3 or z)   -- clip to +/- 3
return i.n < 2 and 0 or sqrt(i.m2 / (i.n - 1))
-- Trap: `cond and false or 1` is always 1. Never put false in the
-- middle slot.

-- if / elseif / else / end. No switch; see section 4 for the
-- replacement. This is tab.lua's whole command-line parser body:
if     k     then the[k] = thing(v)       -- looked like name=value
elseif eg[s] then eg[s]()                 -- looked like an action
else              the.file = s end        -- must be a file

-- while, and the three-part numeric for (from, to, step):
while p < #xs and xs[p+1] == v do p = p + 1 end
for k = #t, 2, -1 do ... end
for s = 1, reps do ... end

-- Generic for: pairs for hashes, ipairs for arrays.
-- The difference is load-bearing in tab.lua -- see section 3.
for _, col in order(i.cols) do col:add(row[col.at]) end
for k, v in pairs(t) do n = n + f(v, k) end
for v in (s .. ","):gmatch"(.-)," do row[#row + 1] = thing(v) end

-- repeat/until and break exist. `continue` does not; invert the
-- test. Lua 5.2+ has goto, which tab.lua never uses.

-- Comparison is == and ~= (not !=). Logic is and/or/not.
if v == "?" then return end         -- "?" is how a csv says "missing"

----------------------------------------------------------------------
-- 2. Functions.
----------------------------------------------------------------------

function thing(s)                   -- one cell: number, or the string
  s = s:match"^%s*(.-)%s*$"; return tonumber(s) or s end

-- Multiple returns are part of the calling convention, not a tuple:
function BAG.parts(i,x,    tp,fp,fn) -- x's tp, fp, fn, tn, so far
  tp = i.hit[x] or 0
  fp = (i.got[x] or 0) - tp
  fn = (i.want[x] or 0) - tp
  return tp, fp, fn, i.n - fn - fp - tp end

tp, fp, fn, tn = i:parts"a"

-- Two rules: a call expands to all its results only in the LAST
-- position of a list, and parentheses cut it to one. Both matter:
return (best(i.subs, f))   -- best returns key,score. Want the key.
io.lines((file:gsub("^~", os.getenv"HOME" or "~")))  -- gsub returns 2
ok, line = pcall(fun, pair(tbl, s))  -- pair returns 2; both expand

-- A call with ONE string or ONE table literal needs no parentheses.
-- tab.lua leans on this everywhere:
os.getenv"HOME"                     -- os.getenv("HOME")
s:match"^%s*(.-)%s*$"               -- s:match("...")
i:add"?"                            -- i:add("?")
Tab{ {"Age","job","klass!"} }       -- Tab({ {...} })

-- Those odd parameter lists -- `function sum(t,f,    n)` -- are a
-- house style. Everything after the gap is a LOCAL, declared as a
-- parameter so it arrives nil. Parameters and locals compile to the
-- same register slots, so this costs nothing and makes the
-- signature a declaration of the function's whole working set:
function SAME.cliffs(i,    xs,ys,gt,lt,j,k) -- how often xs out-ranks ys
  xs, ys, gt, lt, j, k = i.xs, i.ys, 0, 0, 0, 0

-- Functions are values. Closures capture enclosing locals by
-- reference. tab.lua's learners take their goal as a function, so
-- the same code predicts anything callable:
y     = function(row) return sub:ydist(row) end
model = Rmeans(tbl, few, y)
...
i.has[b]:add(y(row))                -- inside Bins, which never knew

-- Anonymous helpers go in a named local first, then get used.
-- Here f captures `all` from the enclosing call:
function BINS.weight(i,all,    f,s) -- variance i's bins cut off
  f = function(v) return v.n/all.n * v:div() ^ 2 end
  s = all:div() ^ 2 - sum(i.has, f)
  return s > 0 and s or 0 end

-- pcall is Lua's entire try/catch: true plus results, or false plus
-- the error. error(msg, 0) suppresses the file:line prefix.
ok, line = pcall(fun, pair(tbl, s))     -- a broken csv is a skip
if not ok then h:close(); os.remove(f); error(line, 0) end
-- ^ note the cleanup: without os.remove, a crash leaves a truncated
--   cache file that the next run accepts as finished work.

-- assert(cond) is the terse form. tab.lua's 25 tests are little
-- else, with floats compared through a tolerance, never ==:
function near(a,b) return abs(a - b) < 1e-6 end
assert(i.n == 10 and i.mu == 5.5 and near(i:div(), 3.0276503541))

----------------------------------------------------------------------
-- 3. Tables: the only data structure.
----------------------------------------------------------------------

-- A hash map with a fast path for integer keys. Use both halves at
-- once -- array of rows here, named fields there:
function Bag()                      -- blank counts, for one test set
  return new(BAG, {n = 0, ok = 0, got = {}, want = {}, hit = {}}) end

-- t.x is sugar for t["x"]. Computed keys need brackets:
i.has.c                             -- literal key
i.has[v]                            -- computed key

-- ARRAYS START AT 1. #t is the array length. The push idiom:
i.cols[#i.cols + 1] = col

-- Missing keys are nil, never an error -- hence the default-zero
-- counter, which is all of SYM.add:
function SYM.add(i,v)               -- one more of v
  if v == "?" then return end
  i.n = i.n + 1
  i.has[v] = (i.has[v] or 0) + 1 end

-- `x = x or expensive()` is also memoization in one line:
function SYM.nVals(i,    f)         -- how many values i has seen;
  f = function() return 1 end       -- one value still splits two ways
  i.kinds = i.kinds or max(2, sum(i.has, f))
  return i.kinds end

-- Tables are REFERENCES. Passing one does not copy it, so a
-- function that sorts its argument damages the caller's list.
-- map(t, same) -- map with the identity -- is the shallow copy:
function same(x) return x end       -- identity

function TAB.split(i,    rows,n,t,u1,u2) -- never shuffles i.rows
  rows   = shuffle(map(i.rows, same))    -- itself

function Same(xs,ys,    f)          -- two samples, sorted, to compare
  f = function(t,    u)             -- on copies: the caller's list is
        u = map(t, same); table.sort(u); return u end -- not ours
  return new(SAME, {xs = f(xs), ys = f(ys)}) end
-- ^ that copy was a bug once: table.sort is in place, so comparing
--   two samples used to reorder them as a side effect.

-- Four higher-order functions replace nearly every loop:
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

-- map walks with ipairs (rows are ordered); sum and best walk with
-- pairs (they total hash-keyed counts). So one sum serves both:
sum(i.has, f) / log(2)              -- entropy, over a symbol count
sum(i.y, f)                         -- over an array of goal columns

-- A nil in an array breaks #t, so map writes u[#u+1] and skips
-- nils. That makes map a filter too, which is how prune works:
i.cols = map(i.cols, function(col)
  return (how == "max" and f(col) >= .1 * most
          or how == "chance" and f(col) > i:chance(i.has[col.at]))
         and col or nil end)        -- `and col or nil`: keep, or drop

-- One function, three signatures -- dispatch on type(), and return
-- an iterator triple so it is a drop-in for ipairs:
function order(t,f,    u,at)        -- ipairs; or, given f, a sorted
  if not f then return ipairs(t) end -- copy's ipairs. f: a comparator,
  if type(f) ~= "function" then     -- or a cell index to sort rows on
    at = f; f = function(a,b) return a[at] < b[at] end end
  u = map(t, same); table.sort(u, f); return ipairs(u) end

-- The first arg is always a table; the second decides its fate.
for _, col in order(i.cols) do ...  -- no f: plain ipairs, no copy
for _, key in order(keys, lt) do ...-- f a comparator: sorted copy
for _, row in order(rows, 3) do ... -- f a number: sort on that cell,
                                    -- so items must be tables (rows)

-- A table of functions replaces every switch statement. tab.lua's
-- test suite IS its command line:
eg  = {}                           -- cli runs eg[action]; see --all
eg["--thing"] = function()
  assert(thing" 42 " == 42 and thing"x" == "x") end
...
elseif eg[s] then eg[s]()           -- dispatch, no if-chain

----------------------------------------------------------------------
-- 3.1 Patterns (Lua's own matcher -- not regexps).
----------------------------------------------------------------------

-- Classes use % not backslash: %a letter, %d digit, %w alphanum,
-- %s space, %u uppercase, %S not-space, . any, %% a literal %.
-- Quantifiers: * greedy, + greedy 1+, - LAZY 0+, ? optional.
-- No alternation, no {n,m}. Anchors ^ and $. Captures in ( ).

k, v = s:match"^(%a%w*)=(.*)$"      -- two captures, two returns
s = line:match"^%s*(.-)%s*$"        -- %s*(.-)%s* is the trim idiom
file:match"([^/]+)%.csv$"           -- basename
if txt:find"[-+!]$" then ...        -- find: indices, or nil
col = (txt:find"^%u" and Num or Sym)(txt, at)  -- picks a constructor!

-- gmatch iterates every match. Two captures, two loop variables.
-- This is how the help string becomes the settings table:
for k, v in help:gmatch"\n%s+(%a+)=(%S+)" do the[k] = thing(v) end
-- Defaults cannot drift from documentation: there is one copy.

-- And with one capture, gmatch is the csv cell splitter:
function cells(s,    row) row = {}
  for v in (s .. ","):gmatch"(.-)," do row[#row + 1] = thing(v) end
  return row end

----------------------------------------------------------------------
-- 4. Metatables and metaprogramming.
----------------------------------------------------------------------

-- A metatable holds handlers for what a table cannot answer itself.
-- __index is the failed-lookup hook, and it is the ONLY one tab.lua
-- uses. Three moves, one line, and that is the object system:
function new(meta,i)                -- i is now one of meta's kind
  meta.__index = meta; return setmetatable(i, meta) end

-- 1. meta.__index = meta -- on a miss, look in the class table,
--    where the methods live.
-- 2. setmetatable(i, meta) -- attach it.
-- 3. return i, so constructors read as expressions.

-- The class is a plain table, so "what kind is this?" is literally
-- its metatable:
assert(getmetatable(t.cols[1]) == NUM)       -- A-Z: num; a-z: sym
assert(getmetatable(t.cols[4]) == SYM)

-- Other metamethods exist -- __add, __eq, __lt, __call, __tostring,
-- __newindex, __len, __gc -- and would let you write num1 + num2.
-- tab.lua uses none: operator overloading hides where the work is.

-- The one piece of metaprogramming it does use heavily: a method
-- name as DATA. col[how](col, v) is col:bin(v) with the verb in a
-- string, resolved through __index to NUM.bin or SYM.bin:
function TAB.clone(i,rows,how,    out) -- same header, fresh summaries
  out = {how and map(i.cols, function(col) return col.txt:lower() end)
             or i.names}         -- how makes nums discrete, so sym
  for _, row in order(rows or {}) do
    out[#out + 1] = not how and row or map(i.cols,
      function(col) return col[how](col, row[col.at]) end) end
  return Tab(out) end

b = t:clone(t.rows, "bin")          -- a discretized copy, in one call
i = Nb(b, b.rows)                   -- ... ready for Bayes

-- Note what else that does: the header names were lowercased, and
-- TAB.head reads case as type, so the clone's columns are all SYM.
-- The data transform and the schema transform are one operation.

-- The environment is a table too. tab.lua's first two lines make
-- its globals private:
local _ENV = setmetatable({}, {__index = _G})
if setfenv then setfenv(1, _ENV) end   -- lua 5.1, luajit

-- In 5.2+ every global `x` compiles to `_ENV.x`. Rebind _ENV and
-- "global" means your table: writes land there, reads miss and fall
-- through __index to _G. So the file gets the whole standard
-- library and pollutes nothing. 5.1/LuaJIT have no _ENV but have
-- setfenv, hence line two, guarded so it is a no-op on 5.2+.
-- What this does NOT do is catch typos: a misspelled read falls
-- through to _G and yields nil.

----------------------------------------------------------------------
-- 5. Class-like tables, and NO inheritance.
----------------------------------------------------------------------

-- a:f(x) means a.f(a, x). That is the only sugar. So a method is
-- just a function whose first argument is the receiver.
-- tab.lua declares methods with a DOT and names the receiver `i`
-- (most Lua writes `:` and the implicit `self` -- same thing):
function NUM.add(i,v,    d)         -- Welford's running mean and sd
  if v == "?" then return end
  i.n = i.n + 1
  d = v - i.mu
  i.mu = i.mu + d / i.n
  i.m2 = i.m2 + d * (v - i.mu) end

-- ...and calls them with a colon:
i = Num(); for x = 1, 10 do i:add(x) end
assert(i.n == 10 and i.mu == 5.5)

-- Naming convention is the whole type system: ALLCAPS class table,
-- Camel constructor, lowercase plain function.
function Sym(txt,at)                -- a-z names; counts, not Welford
  txt, at = txt or "S", at or 0
  return new(SYM, {txt = txt, at = at, n = 0, has = {},
                   w = txt:find"%-$" and 0 or 1}) end

-- There is NO inheritance here. Every class metatable points at
-- itself, one level. NUM and SYM are unrelated tables that happen
-- to answer the same four messages -- add, div, norm, bin:
function NUM.div(i)                 -- standard deviation
  return i.n < 2 and 0 or sqrt(i.m2 / (i.n - 1)) end

function SYM.div(i,    f)           -- entropy
  f = function(n) return -n/i.n * log(n/i.n) end
  return sum(i.has, f) / log(2) end

function NUM.bin(i,v,    b)         -- 1..the.bins
  if v == "?" then return v end
  b = 1 + floor(the.bins * i:norm(v))
  return b > the.bins and the.bins or b end

function SYM.bin(i,v) return v end  -- a sym is its own bin
function SYM.norm(i,v) return v end -- syms pass through

-- Two of those are one-liners returning the argument. That is the
-- price of duck typing, and it is cheaper than a hierarchy: no
-- caller ever branches on type.
for _, col in order(i.cols) do col:add(row[col.at]) end

-- If you DO want inheritance, it is one more line -- point the
-- subclass's __index at the superclass instead of itself. tab.lua
-- declines, on the grounds that one level is enough.

----------------------------------------------------------------------
-- 6. Modules.
----------------------------------------------------------------------

-- tab.lua's last line:
return _ENV
-- ^ everything the file defined IS the module table. No export list
--   to keep in sync.

-- tab-eg.lua then adopts it as its own environment:
package.path = (arg[0]:match"^(.*)/" or ".") .. "/?.lua;" .. package.path
local min = require "tab"
if setfenv then setfenv(1, min) end          -- tab's _ENV is ours too
local _ENV = min
the = cli()                         -- tab's options, off our cli

-- Line by line: extend the search path with the script's own
-- directory so tab.lua is found wherever you ran from; load it;
-- make its table this file's globals, on 5.1 and 5.2+ both. Now
-- Tab, Nb and `the` need no prefix, and whatever tab-eg.lua defines
-- lands in the same shared table.
-- Sharp-edged: two files, one namespace, no record of who owns
-- what. For a library with several consumers, prefer the plain
-- `local M = {}; ... return M`.

-- require caches: the module body runs once, however many files
-- ask for it.

-- Being both a script and a library needs one guard -- Lua's
-- equivalent of if __name__ == "__main__":
if (arg and arg[0] or ""):find"tab%.lua$" then
  if #arg == 0 then eg["-h"]() else cli() end end

----------------------------------------------------------------------
-- 7. The standard library, as much of it as tab.lua needs.
----------------------------------------------------------------------

math.floor  math.exp  math.sqrt  math.log  math.abs  math.min  math.max
table.sort(u, f)        -- IN PLACE, unstable; f(a,b) is "a before b"
table.concat(t, ",")    -- array to string; numbers and strings only
tonumber(s)  tostring(x)  type(x)  assert(cond, msg)  pcall(f, ...)
setmetatable(t, meta)   getmetatable(t)   pairs(t)   ipairs(t)
io.open(f, "w")  h:write(s)  h:close()  io.lines(f)  print(...)
os.clock()  os.getenv"HOME"  os.execute(cmd)  os.remove(f)
string.format(...)   or   ("%d,%.4f,%s\n"):format(...)
arg                    -- the command line; arg[0] is the script

-- math.random is deliberately NOT used. Its generator differs by
-- Lua build, platform and version, so results would not reproduce.
-- tab.lua ships its own Park-Miller:
function rint(n)                    -- 1..n, repeatable from the.seed
  the.seed = (16807 * the.seed) % 2147483647
  return 1 + floor(n * the.seed / 2147483647) end

-- The arithmetic peaks near 3.6e13, under 2^53 (~9.0e15), the
-- largest integer a double holds exactly. So Lua, Python and Lisp
-- all shuffle a table into the SAME order, and a train/test split
-- is a number you can quote, not a file you have to ship.

-- Time with os.clock (cpu seconds), not os.time (wall clock, one
-- second of resolution):
t0  = os.clock()
...
tot = tot + (os.clock() - t0) end

----------------------------------------------------------------------
-- 8. Sharp edges, in one place.
----------------------------------------------------------------------

-- Indices start at 1. t[0] is just another key.
-- ~= not !=. .. not + for strings. No ++ or +=.
-- 0 and "" are TRUE. `if n then` is not `if n > 0 then`.
-- Undeclared variables are global and silently nil: a typo reads
--   as nil instead of raising.
-- A nil inside an array makes #t return any valid border. Append
--   with t[#t+1] and never store nil as a countable value.
-- Integer division is // in 5.3+ only; tab.lua writes floor(a/b).
-- pairs order is UNDEFINED: best(i.subs, f) over a hash breaks
--   exact ties unpredictably, and summing a hash of floats depends
--   on addition order in the last bit.
-- table.sort is unstable, and a comparator that is not a strict
--   weak ordering can raise "invalid order function" or corrupt
--   the array. `lt` here is plain <, which errors on mixed types.
-- t[1] and t["1"] are different keys. Everything off a csv goes
--   through `thing` once, at the edge, so the type is settled.
-- Instance fields shadow class methods: new(NUM, {div = 3}) makes
--   i:div() a call on a number.
-- `cond and false or 1` is always 1.
-- setfenv exists only on 5.1/LuaJIT, _ENV only on 5.2+. Code for
--   both writes tab.lua's first two lines and tests on both.
```

## Try it

    luajit tab.lua            # the help text, which is also the config
    luajit tab.lua --all      # 25 unit tests
    luajit tab.lua --num      # just one
    luajit tab.lua --secs     # time a train-then-guess

Then read `tab.lua` straight through. It is 563 lines and you now
know every construct in it.
