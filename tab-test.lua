#!/usr/bin/env lua
-- vim: set ts=2 sw=2 sts=2 et cc=75 :
-- tab-test.lua: the unit tests.  Each prints a tiny demo, then
-- asserts golden values: port tab to another language, pass these,
-- and the port agrees with this code to 1e-6.
-- usage: luajit tab-test.lua [--all | --num --split ... | name=value]
package.path = (arg[0]:match"^(.*)/" or ".") .. "/?.lua;" .. package.path
local tab = require "tab-eg"    -- tab, plus its stats and scoring
if setfenv then setfenv(1, tab) end
local _ENV = tab

-- Return true when `a:num` and `b:num` are close enough.
function near(a,b) return abs(a - b) < 1e-6 end --> bool

fast["--all"] = function(    b4,keys,t0,ms,worst,who)
  b4, keys, worst = the.seed, {}, 0 -- every test action, a-z order,
  for key in pairs(fast) do           -- each from a fresh seed; skip
    if not (" -h --all "):find(" " .. key .. " ", 1, true) then
      keys[#keys + 1] = key end end            -- the non-tests
  for _, key in order(keys, lt) do
    the.seed, t0 = b4, os.clock()
    fast[key]()                       -- a fast test is small by design,
    ms = 1000 * (os.clock() - t0)   -- so time it and say who is not
    if ms > worst then worst, who = ms, key end end
  print(("PASS %d tests, worst %s at %.1fms")
        :format(#keys, who, worst))
  assert(worst < the.budge, who .. " is slow: move it to slow") end

slow["--secs"] = function(    reps,file,tbl,tot,t0,tr,te,sub,y,
                             model,lim,seed)
  reps, file = the.reps, the.file  -- time rmeans: train, then guess
  tbl, tot, seed = Tab(file), 0, the.seed
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

fast["--o"] = function(    i,b4)   -- nested, in order, at the.fmt
  i, b4 = Num(), the.fmt
  i:add(1); i:add(2); the.fmt = "%.2f"
  print("o", o{1, 2.5, {a = 1, b = {2, 3}}}, i)
  assert(o{1, 2.5} == "{1 2.50}")   -- a fraction gets the.fmt
  assert(o{b = 1, a = 2} == "{a=2 b=1}")
  assert(o{a = {1, {z = 3}}} == "{a={1 {z=3}}}")
  assert(tostring(i):find"n=2" and not tostring(i):find"it=")
  the.fmt = "%.3f"; assert(o{x = 1/3} == "{x=0.333}")
  the.fmt = b4 end                  -- leave fmt as we found it

fast["--values"] = function(    t)
  t = values"1, a,2.5,?"
  print("values", table.concat(t, "|"))
  assert(#t == 4 and t[1] == 1 and t[2] == "a" and t[3] == 2.5)
  assert(t[4] == "?")
  assert(values" 42 "[1] == 42 and values"x"[1] == "x")
  assert(values"4.2"[1] == 4.2 and values"  a b "[1] == "a b") end

fast["--csv"] = function(    t)
  t = csv(the.file)
  print("csv", #t, #t[1], t[1][1])
  assert(#t == 399 and #t[1] == 8)
  assert(t[1][1] == "Clndrs" and t[2][1] == 8) end

fast["--map"] = function(    t)
  t = map({10,20,30}, function(v,k) return v + k end)
  print("map", table.concat(t, ","))
  assert(t[1] == 11 and t[2] == 22 and t[3] == 33)
  t = map({1,2,3,4}, function(v) return v % 2 == 0 and v or nil end)
  assert(#t == 2 and t[1] == 2 and t[2] == 4) end -- nils drop

fast["--sum"] = function(    n)
  n = sum({1,2,3}, same)
  print("sum", n, sum({a=1,b=2}, same))
  assert(n == 6 and sum({a=1,b=2}, same) == 3)
  assert(sum({4,5}, function(v,k) return k end) == 3) end

fast["--best"] = function(    k,n)
  k, n = best({3,9,5}, same)
  print("best", k, n)
  assert(k == 2 and n == 9)
  k = best({x=1,y=9}, same)
  assert(k == "y") end

fast["--rint"] = function(    a,b,c,d)
  the.seed = 1234567891
  a, b, c, d = rint(100), rint(100), rint(100), rint(100)
  print("rint", a, b, c, d)
  assert(a == 19 and b == 70 and c == 6 and d == 8) end

fast["--shuffle"] = function(    t)
  the.seed = 1234567891
  t = shuffle{1,2,3,4,5,6,7,8,9,10}
  print("shuffle", table.concat(t, ","))
  assert(table.concat(t, ",") == "10,9,4,3,6,5,8,1,7,2") end

fast["--num"] = function(    i)
  i = Num(); for x = 1, 10 do i:add(x) end
  print("num", i.mu, i:div())
  assert(i.n == 10 and i.mu == 5.5 and near(i:div(), 3.0276503541))
  i:add"?"; assert(i.n == 10)                 -- "?" is a no-op
  assert(Num("Lbs-").w == 0 and Num("Acc+").w == 1) end

fast["--norm"] = function(    i)
  i = Num(); for x = 1, 10 do i:add(x) end
  print("norm", i:norm(8), i:norm(999))
  assert(near(i:norm(8),   0.8027749262))
  assert(near(i:norm(999), 0.9939401985))     -- clipped at 3 sds
  assert(i:norm"?" == "?") end

fast["--bin"] = function(    i)
  i = Num(); for x = 1, 10 do i:add(x) end
  print("bin", i:bin(8), i:bin(999), i:bin(-999))
  assert(i:bin(8) == 6 and i:bin(999) == the.bins and i:bin(-999) == 1)
  assert(i:bin"?" == "?") end

fast["--sym"] = function(    i)
  i = Sym(); for _, v in order{"a","a","b","c","c","c"} do i:add(v) end
  print("sym", i.n, i.has.c, i:div(), i:nVals())
  assert(i.n == 6 and i.has.c == 3 and i:nVals() == 3)
  assert(near(i:div(), 1.4591479170))
  assert(i:norm"c" == "c" and i:bin"c" == "c")  -- syms pass through
  assert(Sym():nVals() == 2) end             -- one value, two ways

fast["--nums"] = function(    i)
  i = nums{1,2,3,4}
  print("nums", i.mu)
  assert(i.mu == 2.5 and i.n == 4) end

fast["--tbl"] = function(    t)
  t = Tab(the.file)
  print("tbl", #t.rows, #t.cols, #t.x, #t.y)
  assert(#t.rows == 398 and #t.cols == 8 and #t.x == 4 and #t.y == 3)
  assert(t.cols[6].w == 0 and t.klass == nil)  -- Lbs- runs to zero
  assert(near(t.cols[2].mu,    193.425879))
  assert(near(t.cols[2]:div(), 104.269838)) end

fast["--head"] = function(    t)
  t = Tab{ {"Age","HpX","speed-","klass!"} }
  print("head", #t.x, #t.y, t.klass.txt)
  assert(#t.x == 1 and #t.y == 2)              -- HpX summarized, skipped
  assert(t.klass.txt == "klass!")
  assert(t.cols[1].it == NUM)              -- A-Z: num; a-z: sym
  assert(t.cols[4].it == SYM) end

fast["--clone"] = function(    t,u)
  t = Tab(the.file)
  u = t:clone(t.rows)
  print("clone", #u.rows, u.cols[2].mu)
  assert(#u.rows == #t.rows and near(u.cols[2].mu, t.cols[2].mu))
  u = t:clone({t.rows[1]}, "bin")              -- bin makes all syms
  assert(table.concat(u.rows[1], ",") == "7,7,7,1,1,7,7,1")
  assert(u.names[1] == "clndrs")
  assert(u.cols[2].it == SYM) end

fast["--ydist"] = function(    t,d)
  t = Tab(the.file)
  d = t:ydist(t.rows[1])
  print("ydist", d, t:ydist(t.rows[398]))
  assert(near(d, 0.7863215821))                -- a gas guzzler is far
  assert(near(t:ydist(t.rows[398]), 0.1410148526)) -- a honda is near
  assert(d >= 0 and d <= 1) end

fast["--split"] = function(    t,tr,te)
  the.seed = 1234567891
  t = Tab(the.file)
  tr, te = t:split()
  print("split", #tr, #te, table.concat(tr[1], ","))
  assert(#tr == 318 and #te == 80)
  assert(table.concat(tr[1], ",") == "6,145,76,81,2,3160,19.6,30")
  assert(table.concat(te[1], ",") == "4,97,75,75,3,2171,16,30")
  assert(t.rows[1][1] == 8) end               -- t.rows undisturbed

fast["--bins"] = function(    t,y,few,model)
  t, few = Tab(the.file), {}
  y = function(row) return t:ydist(row) end
  for k = 1, 45 do few[k] = t.rows[k] end
  model = Rmeans(t, few, y)              -- bins come from the labeled
  print("bins", model.has[t.x[2].at].w)  -- few, not the world
  assert(near(model.has[t.x[2].at].w, 0.0013005425)) end

fast["--rmeans"] = function(    t,y,few,model)
  t, few = Tab(the.file), {}
  y = function(row) return t:ydist(row) end
  for k = 1, 45 do few[k] = t.rows[k] end
  model = Rmeans(t, few, y)
  print("rmeans", model.all.mu, model:guess(t.rows[1]))
  assert(near(model.all.mu,          0.9009519530))
  assert(near(model:guess(t.rows[1]),   0.8530303902))
  assert(near(model:guess(t.rows[200]), 0.8535267151)) end

fast["--nb"] = function(    t,b,i)
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

fast["--bag"] = function(    i,tp,fp,fn,tn,acc,pd,pf,d2h,k)
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

fast["--same"] = function(    xs,ys,zs,i)
  xs, ys, zs = {}, {}, {}
  for k = 1, 20 do xs[k] = k; ys[k] = k + .5; zs[k] = k + 20 end
  i = Same(xs, ys)
  print("same", i:ok(), Same(xs, zs):ok())
  assert(i:ok() and not Same(xs, zs):ok())
  assert(near(i:cohen(),  0.0845154255))
  assert(near(i:cliffs(), 0.05))
  assert(near(i:ks(),     0.1581138830))
  assert(near(Same(xs, xs):cohen(), 0)) end


if (arg and arg[0] or ""):find"tab%-test%.lua$" then
  if #arg == 0 then arg[1] = "--all" end
  cli() end

return _ENV
