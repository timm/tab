<p align="center"><img src="logo.png"></p>

[lua 101](lua101.md) ·
[lua, more](luamore.md) ·
[tab.lua](tab.md) ·
[tab-eg.lua](tab-eg.md) ·
[license](https://github.com/timm/tab/blob/main/LICENSE.md)

# Lua, more

The idioms that make `tab.lua` short. Read
[lua101.md](lua101.md) first; this file assumes you know what a
table is and what `:` does.

The claim under test: 563 lines of Lua can carry a Bayes
classifier, a regression-tree-ish learner, three effect-size tests,
a csv reader, a config system and 25 unit tests. That only works if
each line pulls hard. Below is how.

Contents:
[1 the `_ENV` sandbox](#1-the-_env-sandbox) ·
[2 metatables](#2-metatables-are-the-object-system) ·
[3 protocol over inheritance](#3-protocol-over-inheritance) ·
[4 parameters as locals](#4-parameters-as-locals) ·
[5 closures](#5-closures-and-upvalues) ·
[6 higher order](#6-the-higher-order-toolkit) ·
[7 polymorphic order](#7-one-function-three-signatures) ·
[8 dispatch by string](#8-dispatch-by-string) ·
[9 config from a docstring](#9-the-docstring-is-the-config) ·
[10 iterators](#10-iterators) ·
[11 multiple returns](#11-multiple-returns-in-anger) ·
[12 pcall](#12-pcall-error-and-cheap-recovery) ·
[13 memoize](#13-memoize-in-one-line) ·
[14 modules](#14-modules-return-_env) ·
[15 determinism](#15-determinism-across-three-languages) ·
[16 performance](#16-performance-what-matters) ·
[17 sharp edges](#17-sharp-edges)

## 1. The `_ENV` sandbox

The first two lines of `tab.lua`:

```lua
local _ENV = setmetatable({}, {__index = _G})
if setfenv then setfenv(1, _ENV) end   -- lua 5.1, luajit
```

In Lua 5.2+ every global access `x` is compiled as `_ENV.x`, where
`_ENV` is an ordinary upvalue. Rebind it and you have changed what
"global" means for the rest of the chunk. So:

- **writes** (`the = {}`, `function map(...)`) land in the new
  empty table, not in `_G`;
- **reads** of anything not there (`math`, `print`, `setmetatable`)
  miss the new table, hit `__index`, and fall through to `_G`.

The file gets the whole standard library and pollutes nothing. Lua
5.1 and LuaJIT have no `_ENV`; they have `setfenv(level, t)`, which
does the same job for the running function -- hence line 4, guarded
by `if setfenv` so it is a no-op on 5.2+.

The payoff is at the bottom of the file:

```lua
return _ENV
```

Everything the file defined *is* the module table. No export list to
keep in sync.

What the sandbox does **not** do is catch typos: a misspelled read
falls through to `_G` and yields `nil` rather than raising. For
that you want a `__index` that errors -- a "strict mode" -- which
`tab.lua` chooses not to pay for.

## 2. Metatables are the object system

A metatable holds handlers for operations a table cannot answer
itself. The only one `tab.lua` uses is `__index`, the
failed-lookup hook:

```lua
function new(meta,i)                -- i is now one of meta's kind
  meta.__index = meta; return setmetatable(i, meta) end
```

Three moves in one line:

1. `meta.__index = meta` -- when a lookup fails on an instance, try
   the class table itself. Methods live there, so they are found.
2. `setmetatable(i, meta)` -- attach it.
3. return `i`, so constructors read as expressions.

So the class is a plain table, and the test for "what kind is
this?" is literally its metatable:

```lua
assert(getmetatable(t.cols[1]) == NUM)       -- A-Z: num; a-z: sym
assert(getmetatable(t.cols[4]) == SYM)
```

Instance fields shadow class methods, which is why constructors
must not name a field after a method. And because lookup walks
`__index` only on *miss*, methods cost one extra hop at most. There
is no inheritance chain here: every class metatable points at
itself, one level, full stop.

Other metamethods exist (`__add`, `__eq`, `__lt`, `__call`,
`__tostring`, `__len`, `__gc`, `__newindex`) and would let you
write `num1 + num2` or `print(col)`. `tab.lua` uses none of them:
operator overloading hides where the work happens, and this code
would rather you saw it.

## 3. Protocol over inheritance

`NUM` and `SYM` are unrelated tables. Neither inherits from the
other, there is no abstract `COL`, and yet they are
interchangeable. They just answer the same four messages:

```lua
function NUM.add(i,v,    d)         -- Welford's running mean and sd
function SYM.add(i,v)               -- one more of v

function NUM.div(i)                 -- standard deviation
function SYM.div(i,    f)           -- entropy

function NUM.norm(i,v,    z)        -- logistic cdf, clipped at 3 sds
function SYM.norm(i,v) return v end -- syms pass through

function NUM.bin(i,v,    b)         -- 1..the.bins
function SYM.bin(i,v) return v end  -- a sym is its own bin
```

Two of those are one-liners that return the argument. That is the
cost of duck typing in Lua, and it is cheaper than a class
hierarchy: callers never branch on type.

```lua
for _, col in order(i.cols) do col:add(row[col.at]) end
```

The choice of class happens once, from the column *name*, and never
again:

```lua
col = (txt:find"^%u" and Num or Sym)(txt, at)
```

Read that inner parenthesis as a value: `and`/`or` select a
constructor, and the result is immediately called. Uppercase
first letter means numeric.

## 4. Parameters as locals

```lua
function SAME.cliffs(i,    xs,ys,gt,lt,j,k) -- how often xs out-ranks ys
  xs, ys, gt, lt, j, k = i.xs, i.ys, 0, 0, 0, 0
```

Everything after the four-space gap is a local, not an argument.
Callers pass `i` only; the rest arrive `nil`.

Why write it this way instead of `local xs, ys = ...`?

- Parameters and locals compile to the same thing -- slots in the
  function's register window. Zero runtime difference.
- The signature becomes a declaration of the function's entire
  working set. You can see at a glance that `cliffs` holds six
  temporaries and touches nothing else.
- It keeps bodies free of bookkeeping lines, which is what lets
  most functions here fit in four lines.

The cost: an extra argument passed by mistake silently initializes
a local. Treat the gap as a wall.

A real local is still needed inside a block, where this trick
cannot reach:

```lua
do
  local few = {}
  for j = 1, (#tr < lim and #tr or lim) do few[j] = tr[j] end
  ...
end
```

## 5. Closures and upvalues

A function defined inside another sees the enclosing locals, by
reference, for as long as it lives. That is an upvalue. `tab.lua`
uses them for one thing above all: carrying a *goal* around.

```lua
y   = function(row) return sub:ydist(row) end
lim = the.budget - the.check
model = Rmeans(tbl, few, y)
```

`Rmeans` has no idea what it is predicting. It takes `y`, a
row-to-number function, and so the same learner serves distance-to-
heaven, a single goal, or anything else callable:

```lua
function Bins(col,rows,y,all,    i,b) -- col's bins, and their worth
  for _, row in order(rows) do
    b = col:bin(row[col.at])
    i.has[b] = i.has[b] or Num()
    i.has[b]:add(y(row)) end
```

Closures also stand in for small anonymous helpers, declared where
used and immediately handed to a higher-order function:

```lua
function BINS.weight(i,all,    f,s) -- variance i's bins cut off
  f = function(v) return v.n/all.n * v:div() ^ 2 end
  s = all:div() ^ 2 - sum(i.has, f)
  return s > 0 and s or 0 end
```

`f` captures `all`. Note the house style: the closure goes in a
named local (declared in the signature), then gets used. A reader
sees the shape before the use.

Two closures created in one loop iteration capture the *same*
variable, not a snapshot. If you need a snapshot, make a fresh
local inside the loop body.

## 6. The higher-order toolkit

Four functions, 12 lines, and nearly every loop in the file:

```lua
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
```

Note the deliberate split: `map` walks with `ipairs` (order
matters, rows are sequences), `sum` and `best` walk with `pairs`
(they total up hash-keyed counts). So:

```lua
sum(i.has, f) / log(2)              -- entropy over a symbol count
sum(i.y, f)                         -- over an array of goal columns
```

...both work, with one `sum`.

`map` dropping nils is the file's filter. `RMEANS.prune` is a
filter written as a map:

```lua
i.cols = map(i.cols, function(col)  -- weight: "max", >= 10% of the
  return (how == "max" and f(col) >= .1 * most  -- best; "chance",
          or how == "chance" and f(col) > i:chance(i.has[col.at]))
         and col or nil end)
```

`and col or nil` -- return the column when it qualifies, `nil`
otherwise, and `map` discards the nils. A `filter` function would
have been a fifth primitive for no gain.

And `map(t, same)` is the shallow copy, used wherever a function
must not disturb its caller:

```lua
rows = shuffle(map(i.rows, same))   -- TAB.split never shuffles i.rows
u = map(t, same); table.sort(u)     -- Same() sorts copies
```

That second one was a bug once. `table.sort` is in place, so
`Same(xs, ys)` used to reorder the caller's samples as a side
effect of comparing them.

## 7. One function, three signatures

```lua
function order(t,f,    u,at)        -- ipairs; or, given f, a sorted
  if not f then return ipairs(t) end -- copy's ipairs. f: a comparator,
  if type(f) ~= "function" then     -- or a cell index to sort rows on
    at = f; f = function(a,b) return a[at] < b[at] end end
  u = map(t, same); table.sort(u, f); return ipairs(u) end
```

Three calls, three behaviours. The first argument is always a
table; the second decides what happens to it:

```lua
-- 1. no f: plain ipairs over the caller's own table, no copy
for _, col in order(i.cols) do col:add(row[col.at]) end    -- tab.lua:197

-- 2. f is a comparator: ipairs over a sorted copy
for _, key in order(keys, lt) do eg[key]() end             -- tab.lua:333
for n, row in order(rows, function(a,b) return g[a] < g[b] end) do
  ...                                                 -- tab-eg.lua:87

-- 3. f is a number: sort on that cell of each item, so the items
--    must themselves be tables (rows)
for _, row in order({ {3,"c"},{1,"a"},{2,"b"} }, 1) do ... end
```

Form 3 has no call site in the repo yet -- it is there because
sorting rows on one column is the obvious next ask, and because it
costs two lines. Note what it assumes: `a[at] < b[at]` needs every
item to be an indexable table, so passing a list of numbers to it
raises `attempt to index local 'a' (a number value)`. Forms 1
and 2 take a list of anything.

Two techniques worth naming. First, **dispatch on `type`** to give
one entry point several argument shapes -- cheap in a dynamic
language, and it stops the call sites from carrying three names.
Second, **returning an iterator from a function**: `return
ipairs(u)` passes along all three of `ipairs`'s return values
(function, state, control), which is exactly what `for ... in`
wants. So `order` is a drop-in for `ipairs` with no wrapper
closure and no allocation in the no-sort case.

The sorted branch builds a copy first, so `order` never reorders
its input.

## 8. Dispatch by string

```lua
function TAB.clone(i,rows,how,    out) -- same header, fresh summaries
  out = {how and map(i.cols, function(col) return col.txt:lower() end)
             or i.names}         -- how makes nums discrete, so sym
  for _, row in order(rows or {}) do
    out[#out + 1] = not how and row or map(i.cols,
      function(col) return col[how](col, row[col.at]) end) end
  return Tab(out) end
```

`col[how](col, v)` is the whole trick. `how` is a string -- `"bin"`
or `"norm"` -- so this looks up the method by name on the instance,
misses, falls through `__index` to `NUM` or `SYM`, and calls it
with `col` as the receiver. It is `col:bin(v)` with the verb as
data.

One consequence: `clone(rows, "bin")` returns a table whose columns
are all `SYM`, because the header names were lowercased and
`TAB.head` reads case as type. The data transform and the schema
transform are the same operation. That is how the Bayes rig gets a
discretized copy of a numeric table in one call:

```lua
b = t:clone(t.rows, "bin")
i = Nb(b, b.rows)
```

The same pattern runs the command line (`eg[s]()`) and the test
suite. A table plus a string key replaces every `switch` statement
the file might have had.

## 9. The docstring is the config

```lua
the,help = {}, [[
...
flags:
  bins=7           numeric columns get this many bins
  m=2              m-estimate: prior weight for a thin bin
  seed=1234567891  random number seed
...]]
```

and, at the bottom:

```lua
for k, v in help:gmatch"\n%s+(%a+)=(%S+)" do the[k] = thing(v) end
```

The help text *is* the settings table. `gmatch` with two captures
yields two loop variables; `thing` coerces each to a number when it
looks like one. Defaults cannot drift from documentation, because
there is only one copy.

The command line then overrides, left to right:

```lua
function cli(k,v)                   -- awk-ish operands, left to right:
  for _, s in order(arg) do        -- name=value, action, file
    k, v = s:match"^(%a%w*)=(.*)$"
    if     k     then the[k] = thing(v)
    elseif eg[s] then eg[s]()
    else              the.file = s end end
  return the end
```

Three operand kinds, no parser, no library. An argument is a
setting if it matches `name=value`, an action if it is a key of
`eg`, otherwise a file. Order matters, so `seed=1 --nb seed=2 --nb`
runs twice with two seeds -- awk's model, and it falls out of the
loop for free.

(Shell note: pass these through `zsh` carefully. `$cfg` does not
word-split in zsh, so `lua tab.lua $cfg` hands `"bins=10 m=2"` to
`cli` as **one** operand, `the.bins` becomes a string, and `NUM.bin`
dies. Write `${=cfg}`.)

## 10. Iterators

`for k, v in f, s, c do` calls `f(s, c)` until it returns `nil`,
rebinding `c` to the first result each time. `pairs` and `ipairs`
just return such a triple, which is why section 7 can pass one
along. Writing your own is mostly writing a closure:

```lua
-- not in tab.lua, but this is the shape
function upto(n,    k)
  k = 0
  return function() k = k + 1; if k <= n then return k end end end
```

`gmatch` is a stateful iterator of this kind, and `tab.lua` uses it
twice as a tokenizer:

```lua
for v in (s .. ","):gmatch"(.-)," do row[#row + 1] = thing(v) end
for k, v in help:gmatch"\n%s+(%a+)=(%S+)" do the[k] = thing(v) end
```

`io.lines` is the same protocol over a file handle, and it closes
the file when the loop ends:

```lua
for line in io.lines((file:gsub("^~", os.getenv"HOME" or "~"))) do
```

Two notes on that line. The inner parentheses matter -- `gsub`
returns a string *and* a count, and `io.lines` would read the count
as a mode argument. And `~` expansion is done by hand, because
`io.lines` is not a shell.

## 11. Multiple returns, in anger

Lua's multiple returns are a real part of the calling convention,
not a tuple object, and they follow two rules worth memorizing:

- In the **last** position of an expression list, a call expands to
  all its results. Anywhere else, it is cut to one.
- Parentheses around a call cut it to one result.

Both rules are load-bearing here:

```lua
return (best(i.subs, f))            -- NB.guess: the key, not the score
```

`best` returns key and score; `NB.guess` promises a class. The
parentheses are the truncation, and dropping them would silently
change the function's arity.

```lua
ok, line = pcall(fun, pair(tbl, s))     -- a broken csv is a skip
```

`pair` returns *two* tables (train and test), in last position, so
both expand into `pcall`'s argument list and arrive as `fun`'s two
arguments. No packing, no unpacking.

```lua
return 100*i.ok/i.n, 100*pd/k, 100*pf/k, d2h/k, k
...
acc, pd, pf, d2h, k = i:score()
```

Five numbers out, five names in. A caller that wants three takes
three; the rest evaporate.

```lua
k, v = s:match"^(%a%w*)=(.*)$"
```

Captures come back as separate values. On no match, `match` returns
a single `nil`, so `k` is `nil` and `v` is `nil` too -- which is
exactly the test the next line makes.

## 12. `pcall`, `error`, and cheap recovery

```lua
ok, line = pcall(fun, pair(tbl, s))     -- a broken csv is a skip
if not ok then h:close(); os.remove(f); error(line, 0) end
```

`pcall(f, ...)` returns `true` plus `f`'s results, or `false` plus
the error. It is Lua's entire try/catch. The pattern above is worth
copying: catch, **clean up the half-written cache file**, then
re-raise. Without the `os.remove`, a crash would leave a truncated
csv that the next run's `exists(f)` check happily accepts as
finished work.

`error(msg, 0)` -- the `0` suppresses the usual `file:line:`
prefix, so a re-raised message is not stamped twice.

`assert(cond, msg)` is the terse form, and the test suite is built
from almost nothing else:

```lua
assert(i.n == 10 and i.mu == 5.5 and near(i:div(), 3.0276503541))
```

with floats compared through a tolerance, never `==`:

```lua
function near(a,b) return abs(a - b) < 1e-6 end
```

## 13. Memoize in one line

```lua
function SYM.nVals(i,    f)         -- how many values i has seen;
  f = function() return 1 end       -- one value still splits two ways
  i.kinds = i.kinds or max(2, sum(i.has, f))
  return i.kinds end
```

`x = x or expensive()` is the whole idiom: compute once, store on
the instance, return the stored value forever after. It works
because a missing key is `nil`, i.e. falsy.

It also fails silently when the real answer *is* `false` or `0` --
then you recompute every call. Here the answer is at least 2, so it
is safe.

The cache is per-instance and never invalidated, which is a
statement about the code: by the time anyone asks `nVals`, the
column has stopped growing.

## 14. Modules: `return _ENV`

`tab.lua` ends with `return _ENV`, so `require "tab"` hands back
every name the file defined. The rig picks that up and *adopts* it
as its own environment:

```lua
package.path = (arg[0]:match"^(.*)/" or ".") .. "/?.lua;" .. package.path
local min = require "tab"
if setfenv then setfenv(1, min) end          -- tab's _ENV is ours too
local _ENV = min
the = cli()                         -- tab's options, off our cli
```

Line by line: extend the search path with the script's own
directory, so `tab.lua` is found regardless of where you ran it
from; load it; then make its table this file's global environment,
on 5.1 and 5.2+ both. From there `Tab`, `Nb`, `the` and the rest
need no prefix, and anything `tab-eg.lua` defines (`pair`,
`scored`, `home`) lands in the same shared table.

That is powerful and sharp-edged in equal measure: two files now
share one namespace, with no import list recording who owns what.
It buys the rigs a prefix-free vocabulary. For a library with more
than one consumer, prefer the plain `local M = {}; ... return M`.

`require` caches, so the module body runs once no matter how many
files ask for it.

## 15. Determinism across three languages

```lua
function rint(n)                    -- 1..n, repeatable from the.seed
  the.seed = (16807 * the.seed) % 2147483647
  return 1 + floor(n * the.seed / 2147483647) end
```

Park-Miller, chosen for a reason the comment in `tab-eg.lua` spells
out:

> A split is a seed, not a file: `rint` is Park-Miller and stays
> under 2^53, so lua, python and lisp all shuffle a table into the
> same order. Only scores reach the disk.

The arithmetic peaks at `16807 * 2147483646` ~ 3.6e13, well under
2^53 ~ 9.0e15, the largest integer a double represents exactly. So
every language with IEEE doubles -- Lua 5.1 and LuaJIT, Python,
Common Lisp -- computes the identical sequence. The train/test
split becomes a *number* you can quote in a paper, not a file you
have to ship.

Two Lua-specific notes. In Lua 5.3+ integers and floats are
distinct subtypes; `%` on two integers stays integer and the result
is the same, so this is version-proof. And `math.random` is
explicitly *not* used, because its generator differs between Lua
builds, platforms and versions.

## 16. Performance: what matters

```lua
floor, exp, sqrt, log = math.floor, math.exp, math.sqrt, math.log
abs, min, max = math.abs, math.min, math.max
```

Hoisting library functions into the file's own namespace turns two
hash lookups per call into one. Under LuaJIT the JIT usually erases
the difference; in the interpreter it is real. Either way it also
shortens the lines, which is the honest reason.

What actually pays, in rough order:

- **Do not copy what you do not have to.** `order(t)` with no
  comparator returns `ipairs(t)` and allocates nothing.
- **Grow arrays with `t[#t+1] = v`.** Avoid `table.insert` in hot
  loops (a function call and an argument check per element) and
  avoid writing past the end with a gap.
- **Reuse one accumulator.** `NUM.add` is Welford's: constant
  memory, one pass, no list of values retained. A million rows cost
  the same as ten.
- **Concatenate once.** `a .. b .. c` in a loop is quadratic;
  collect into a table and `table.concat` at the end.
- **`pcall` is cheap; creating closures in an inner loop is not.**
  `tab.lua` builds each closure once per function call, outside the
  loop that uses it.

And measure, in the same process, with `os.clock` (cpu time), not
`os.time` (wall clock, one-second resolution):

```lua
t0  = os.clock()
...
tot = tot + (os.clock() - t0) end
```

## 17. Sharp edges

**`pairs` order is undefined.** `best(i.subs, f)` iterates a hash,
so on an exact tie the winner depends on internal table layout. For
Bayes on real data ties are vanishingly rare, but if you need a
deterministic tie-break, sort the keys first. The same caution
applies to `sum` over a hash in floating point: a different
addition order gives a different last bit.

**`table.sort` is unstable and strict.** Equal elements may swap,
and a comparator that is not a strict weak ordering (returns true
for both `f(a,b)` and `f(b,a)`) can raise "invalid order function"
or corrupt the array. `lt` here is plain `<`, which is fine for
numbers and strings but errors on mixed types -- `order(keys, lt)`
works only because the test keys are all strings.

**`#t` on a table with holes is any valid border.** The file's rule
is: arrays are dense, built with `#t+1`, and `nil` is never stored
as a value.

**String keys and numeric keys are different keys.** `t[1]` and
`t["1"]` are two slots. Anything read from a csv has already gone
through `thing`, so the cell type is settled once, at the edge.

**Shadowing is silent.** `same`, `Same` and `SAME` are three
different things in this file; so are `lt` the comparator and
`SAME.cliffs`'s local `lt`. Case is the convention doing the work
(ALLCAPS class, Camel constructor, lower function), and the
convention is all there is.

**Instance fields shadow methods.** `new(NUM, {div = 3})` would
make `i:div()` a call on a number. Keep constructor keys and method
names disjoint.

**`0` is true,** so `if n then` is not `if n > 0 then`. The most
common Lua bug for Python and C refugees.

**The `_ENV` sandbox does not stop typos** (section 1), and
`setfenv` exists only on 5.1/LuaJIT while `_ENV` exists only on
5.2+. Code that must run on both writes the pair of lines at the
top of `tab.lua` and tests on both.

## Where to look next

- `TAB.head` / `TAB.clone` -- how a column's *name* carries its
  type, its goal direction and whether to skip it. Six lines,
  no schema file.
- `NB.like` -- the m-estimate, and the one genuinely subtle thing in
  the file: `col1` knows this class's counts, `col` knows how many
  distinct values exist at all, so the smoothing denominator needs
  both.
- `eg["--all"]` -- a test runner in six lines, resetting the seed
  before each test so every test starts from the same world.
