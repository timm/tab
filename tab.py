#!/usr/bin/env python3
# vim: set ts=2 sw=2 sts=2 et cc=75 :
"""tab.py: minimal tab.lua -- rmeans regression, naive bayes, trees.
Columns: Uppercase=Num, else Sym; names ending X skip, -+! are goals,
! is the klass, - means minimize. (c) 2026 Tim Menzies, MIT.

Options:
  bins=7     numeric columns get this many bins
  check=5    labels spent confirming the top of a ranking
  depth=4    how deep a tree may grow
  fmt=%.2f   how floats print
  leaf=8     rows each side of a cut needs
  m=2        m-estimate: prior weight for a thin bin
  p=2        minkowski coefficient
  test=None  held-out csv (None: demos test on train)
  train=~/gits/moot/optimize/misc/auto93.csv"""

import sys, os, re, time
from math import exp, log
from types import SimpleNamespace as o

def value(x):                            # "4.2" -> 4.2; "x" -> "x"
  x = x.strip()
  try: return int(x)
  except ValueError:
    try: return float(x)
    except ValueError: return x

the = o(**{k:value(v) for k,v in re.findall(r"\n\s+(\w+)=(\S+)",__doc__)})

def csv(file):                               
  with open(os.path.expanduser(file), encoding="utf-8-sig") as f:    
    for line in f:                        
      s = line.strip()                   
      if s and s[0] != "#": yield [value(x) for x in s.split(",")]

class Sym:
  "Summarize a stream of symbols: counts, mode, entropy."
  ops = ("==", "!=")
  def __init__(i, txt="S", at=0):
    i.txt, i.at, i.n, i.has = txt, at, 0, {}
    i.w = 0 if txt.endswith("-") else 1
  def add(i, v, inc=1):
    if v != "?":
      i.n += inc
      i.has[v] = i.has.get(v, 0) + inc
      if i.has[v] <= 0: del i.has[v]
    return v
  def mid(i): return max(i.has, key=i.has.get)   # the majority value
  def div(i):                                  # entropy, in bits
    return -sum(n / i.n * log(n / i.n) for n in i.has.values()) / log(2)
  def norm(i, v): return v                     # a sym is its own norm
  def bin(i, v): return v                      # and its own bin
  def holds(i, x, v): return x == "?" or x == v  # "?" says yes: no cut
  def cut(i, xy, Y):                             # ever loses a row
    for v in sorted({x for x, _ in xy}, key=str):
      near, far = Y(), Y()
      for x, y in xy: (near if x == v else far).add(y)
      yield near, far, v
  def nVals(i): return max(2, len(i.has))

class Num:
  "Summarize a stream of numbers: Welford's running mean and sd."
  ops = ("<=", ">")                            # how a cut of it reads
  def __init__(i, txt="N", at=0):
    i.txt, i.at, i.n, i.mu, i.m2 = txt, at, 0, 0.0, 0.0
    i.w = 0 if txt.endswith("-") else 1
  def add(i, v, inc=1):
    if v == "?": return v
    i.n += inc
    if i.n <= 0: i.n, i.mu, i.m2 = 0, 0.0, 0.0; return v
    d = v - i.mu; i.mu += inc * d / i.n; i.m2 += inc * d * (v - i.mu)
    return v
  def mid(i): return i.mu
  def div(i): return 0 if i.n < 2 else (max(i.m2, 0) / (i.n - 1)) ** .5
  def norm(i, v):
    if v == "?": return v
    z = (v - i.mu) / (i.div() + 1e-32)
    return 1 / (1 + exp(-1.7 * max(-3, min(3, z))))
  def bin(i, v):
    return v if v == "?" else min(the.bins, 1 + int(the.bins * i.norm(v)))
  def holds(i, x, v): return x == "?" or x <= v  # "?" says yes: no cut
  def cut(i, xy, Y):                             # ever loses a row
    xy.sort(key=lambda p: p[0])
    near, far = Y(), Y()
    for _, y in xy: far.add(y)
    for j, (x, y) in enumerate(xy[:-1]):
      near.add(y); far.add(y, -1)
      if x != xy[j + 1][0]: yield near, far, x


class Tab:
  "Rows, summarized in columns: x independents, y goals, maybe a klass."
  def __init__(i, src):
    i.rows, i.cols = [], None
    for row in (csv(src) if isinstance(src, str) else src): i.add(row)
  def add(i, row):
    if i.cols is None: return i.head(row)
    i.rows.append(row)
    for col in i.cols: col.add(row[col.at])
    return row
  def head(i, names):
    i.names, i.cols, i.x, i.y, i.klass = names, [], [], [], None
    for at, txt in enumerate(names):
      col = (Num if txt[0].isupper() else Sym)(txt, at)
      i.cols.append(col)
      if txt.endswith("X"): pass
      elif txt[-1] in "-+!":
        i.y.append(col)
        if txt.endswith("!"): i.klass = col
      else: i.x.append(col)
  def clone(i, rows=None):                 # a fresh Tab holding ROWS
    return Tab([i.names] + list(rows or []))
  def binned(i, rows=None):                # ROWS, discretized.  The
    out = Tab([[c.txt.lower() for c in i.cols]])   # lowercase names are
    for row in rows or []:                   # the point: a lowercase
      out.add([c.bin(row[c.at]) for c in i.cols])  # name is a Sym
    return out
  def mid(i, cols=None):               # {name: middle}, for logfmt
    return {c.txt: c.mid() for c in (cols or i.cols)}
  def cut(i, rows, ys, Y=None):
    Y = Y or (Sym if isinstance(ys[0], str) else Num)
    best, col1, v1 = 1e30, None, None
    for col in i.x:
      xy = [(x, ys[k]) for k, r in enumerate(rows)
            if (x := r[col.at]) != "?"]
      for near, far, v in col.cut(xy, Y):
        if near.n >= the.leaf and far.n >= the.leaf:
          s = (near.div() * near.n + far.div() * far.n) / (near.n + far.n)
          if s < best: best, col1, v1 = s, col, v
    return col1, v1
  def ydist(i, row):
    d = sum(abs(c.norm(row[c.at]) - c.w) ** the.p for c in i.y) / len(i.y)
    return d ** (1 / the.p)

class Tree:
  "A binary tree over rows; each split leaves the tightest ys behind."
  def __init__(i, tab, rows, ys, Y=None, txt="", lvl=1):
    Y = Y or (Sym if isinstance(ys[0], str) else Num)
    i.rows, i.txt, i.lvl, i.kids, i.all = rows, txt, lvl, [], Y()
    for y in ys: i.all.add(y)
    i.mu = i.all.mid()                   # a mean, or a majority
    if len(rows) >= 2 * the.leaf and lvl < the.depth:
      i.col, i.v = tab.cut(rows, ys, Y)
      if i.col:
        a, b = [], []
        for k, r in enumerate(rows):
          (a if i.go(r) else b).append((r, ys[k]))
        if len(a) >= the.leaf and len(b) >= the.leaf:  # else, a
          i.kids = [Tree(tab, [r for r, _ in t], [y for _, y in t], Y,
                         f"{i.col.txt} {op} {i.v}", lvl + 1)
                    for t, op in zip((a, b), i.col.ops)]    # bad cut
  def go(i, row): return i.col.holds(row[i.col.at], i.v)
  def leaf(i, row):
    while i.kids: i = i.kids[0] if i.go(row) else i.kids[1]
    return i
  def dict(i):
    d = {"n": len(i.rows), "mu": i.mu}
    if i.txt: d["txt"] = i.txt
    if i.kids: d["left"], d["right"] = i.kids[0].dict(), i.kids[1].dict()
    return d

class Rmeans:
  "Regression: per-x-column bin means of y, m-estimated, weighed by variance."
  def __init__(i, tab, rows, y):
    sub = tab.clone(rows)
    i.all, i.cols, i.has = Num(), sub.x, {}
    for r in sub.rows: i.all.add(y(r))
    for col in sub.x:
      bins = {}
      for r in sub.rows: bins.setdefault(col.bin(r[col.at]), Num()).add(y(r))
      cut = i.all.div() ** 2 - sum(v.n / i.all.n * v.div() ** 2
                                   for v in bins.values())
      i.has[col.at] = (bins, max(cut, 0))
  def like(i, col, row):
    bins, wt = i.has[col.at]
    v = bins.get(col.bin(row[col.at]))
    if v and wt > 0:
      return (v.n * v.mu + the.m * i.all.mu) / (v.n + the.m), wt
    return None, 0
  def guess(i, row):
    s = w = 0
    for col in i.cols:
      g, wt = i.like(col, row)
      if g is not None: s += wt * g; w += wt
    return s / w if w > 0 else i.all.mu

class Nb:
  "Naive Bayes: one sub-table per klass; guess likeliest (binned data)."
  def __init__(i, tab, rows):
    i.tab, i.subs, i.n, i.nKlass = tab, {}, len(rows), 0
    for r in rows:
      v = r[tab.klass.at]
      if v not in i.subs: i.subs[v] = tab.clone(); i.nKlass += 1
      i.subs[v].add(r)
  def like(i, sub, row):
    m = the.m
    L = log((len(sub.rows) + m) / (i.n + m * i.nKlass))
    for j, col1 in enumerate(sub.x):
      v = row[col1.at]
      if v != "?":
        L += log((col1.has.get(v,0)+m) / (col1.n + m*i.tab.x[j].nVals()))
    return L
  def guess(i, row):
    return max(i.subs, key=lambda k: i.like(i.subs[k], row))

# ---- test --------------------------------------------------------
# Demos double as tests: each prints a little, asserts once.
# usage: tab.py [key=value | all | value | num | ...]
def near(a, b): return abs(a - b) < 1e-6

def ok(got, want):            # assert, then hand the value back, so
  assert got == want or (     # a demo can print and check in one line
    isinstance(got, float) and near(got, want)), f"{got} != {want}"
  return got

def logfmt(_indent=0, **d):            # k=v ...; a dict value indents +1
  pad = "  " * _indent
  flat = " ".join(f"{k}={the.fmt % v if isinstance(v, float) else v}"
                  for k, v in sorted(d.items())
                  if not isinstance(v, dict))
  lines = [pad + flat] if flat else []
  for k, v in sorted(d.items()):
    if isinstance(v, dict):
      lines += [pad + k, logfmt(_indent + 1, **v)]
  return "\n".join(lines)

def test_all():
  for k in sorted(globals()):
    if k.startswith("test_") and k != "test_all": run(k)
  print("PASS")

def test_h(): print(__doc__); assert "Options:" in __doc__

def test_value(): print(logfmt(got=ok(value(" 4.2 "), 4.2)))

def test_num():
  n = Num()
  for x in range(1, 11): n.add(x)
  print(logfmt(mu=n.mid(), sd=ok(n.div(), 3.0276503541)))

def test_sym():
  s = Sym()
  for x in "aabccc": s.add(x)
  print(logfmt(mode=s.mid(), ent=ok(s.div(), 1.4591479170)))

def test_tab():
  t = Tab(the.train)
  print(logfmt(rows=ok(len(t.rows), 398), x=ok(len(t.x), 4),
               y=ok(len(t.y), 3)))

def test_mid():
  t = Tab(the.train)
  print(logfmt(**t.mid(t.y)))
  ok(t.mid(t.y)["Acc+"], 15.5680904523)

def test_ydist():
  t = Tab(the.train)
  print(logfmt(guzzler=ok(t.ydist(t.rows[0]),       # a guzzler, far
                          0.7863215821)))           # from heaven

def test_rmeans_basic():
  t = Tab(the.train)
  m = Rmeans(t, t.rows[:45], t.ydist)               # 45 labels in,
  print(logfmt(guess=ok(m.guess(t.rows[0]),         # same guess as
                        0.8530303902)))             # tab.lua, to 1e-6

def test_rmeans():
  t0 = time.perf_counter()
  train = Tab(the.train)
  test = train if the.test == "None" else Tab(the.test)
  goal = train.y[0]                       # first y column is the goal
  y = lambda r: r[goal.at]
  m = Rmeans(train, [r for r in train.rows if y(r) != "?"], y)
  err = Num()
  for r in test.rows:
    if y(r) != "?": err.add(abs(m.guess(r) - y(r)))
  print(logfmt(flags=vars(the), goal=goal.txt, rows=err.n,
               mae=err.mid(), sd=err.div(),
               secs=time.perf_counter() - t0))
  assert 0 < err.n <= len(test.rows)

def test_optimize():
  train = Tab(the.train)
  test = train if the.test == "None" else Tab(the.test)
  m = Rmeans(train, train.rows, train.ydist)   # ydist on the train...
  guessed = sorted(test.rows, key=m.guess)     # ...sorts the test (x only)
  best = min(guessed[:the.check], key=train.ydist)  # label check items
  truth = sorted(test.rows, key=train.ydist)
  rank = truth.index(best) + 1
  print(logfmt(check=the.check, rank=rank, rows=len(truth),
               best=train.ydist(best)))
  assert 1 <= rank <= len(truth)

def test_nb():
  t = Tab([["Age", "job", "klass!"],
           [20, "low", "no"], [22, "low", "no"], [25, "low", "no"],
           [30, "med", "no"], [60, "hi", "yes"], [62, "hi", "yes"],
           [65, "med", "yes"], [70, "hi", "yes"]])
  b = t.binned(t.rows)
  nb = Nb(b, b.rows)
  print(logfmt(young=ok(nb.guess(b.rows[0]), "no"),
               old=ok(nb.guess(b.rows[-1]), "yes")))

def test_tree():
  t = Tab(the.train)
  node = Tree(t, t.rows, [t.ydist(r) for r in t.rows])
  print(logfmt(**node.dict()))
  assert node.kids and len(node.rows) == 398

# ---- main --------------------------------------------------------
def run(k):                     # a :name header, then the test,
  print(":" + k[5:]); globals()[k]()  # so ,/pretty can find sections

def cli(argv):
  if not argv: return print(__doc__)
  for s in argv:
    if   (k := "test_" + s.lstrip("-")) in globals(): run(k)
    elif "=" in s: k, v = s.split("=", 1); setattr(the, k, value(v))
    else: sys.exit("? " + s)

if __name__ == "__main__": cli(sys.argv[1:])
