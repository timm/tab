#!/usr/bin/env python3
# vim: set ts=2 sw=2 sts=2 et cc=75 :
"""tab2.py: minimal tab.lua -- trees, forests, auc.
Columns: Uppercase=Num, else Sym; names ending X skip, -+! are goals,
! is the klass, - means minimize. (c) 2026 Tim Menzies, MIT.

Options:
  bins=7     numeric columns get this many bins
  cls=~/gits/moot/classify/soybean.csv  labelled data, for a forest
  depth=4    how deep a tree may grow
  fmt=%.2f   how floats print
  leaf=8     rows each side of a cut needs
  p=2        minkowski coefficient
  rounds=30  trees in a forest
  seed=1234567891  random number seed
  test=None  held-out csv (None: demos test on train)
  train=~/gits/moot/optimize/misc/auto93.csv"""

import sys, os, re, time, random
from math import exp, log, sqrt, floor
from types import SimpleNamespace as o

def value(x):
  x = x.strip()
  try: return int(x)
  except ValueError:
    try: return float(x)
    except ValueError: return x

the = o(**{k:value(v) for k,v in re.findall(r"\n\s+(\w+)=(\S+)",__doc__)})

def some(rows, n=None):
  return random.choices(rows, k=n or len(rows))

def pick(lst, n=0):
  return lst if not n or n >= len(lst) else random.sample(lst, n)

def csv(file):
  with open(os.path.expanduser(file), encoding="utf-8-sig") as f:
    for line in f:
      s = line.strip()
      if s and s[0] != "#": yield [value(x) for x in s.split(",")]

class Sym:
  ops = ("==", "!=")
  def __init__(i, txt="S", at=0):
    i.txt, i.at, i.n, i.has, i.cl = txt, at, 0, {}, 0
    i.w = 0 if txt.endswith("-") else 1
  def add(i, v, inc=1):
    if v != "?":
      i.n += inc
      c = i.has.get(v, 0)
      if c > 0: i.cl -= c * log(c)
      c += inc
      if c <= 0: del i.has[v]
      else: i.has[v], i.cl = c, i.cl + c * log(c)
    return v
  def mid(i):
    return max(sorted(i.has, key=str), key=i.has.get)
  def div(i):
    return 0 if i.n < 1 else max(0, log(i.n) - i.cl / i.n) / log(2)
  def norm(i, v): return v
  def bin(i, v): return v
  def holds(i, x, v): return x == "?" or x == v
  def cut(i, xy, Y):
    vs = {}
    for x, _ in xy: vs[x] = 1
    for v in vs:
      near, far = Y(), Y()
      for x, y in xy: (near if x == v else far).add(y)
      yield near, far, v

class Num:
  ops = ("<=", ">")
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
    return v if v=="?" else min(the.bins, 1 + int(the.bins * i.norm(v)))
  def holds(i, x, v): return x == "?" or x <= v
  def cut(i, xy, Y):
    xy.sort(key=lambda p: p[0])
    near, far = Y(), Y()
    for _, y in xy: far.add(y)
    for j, (x, y) in enumerate(xy[:-1]):
      near.add(y); far.add(y, -1)
      if x != xy[j + 1][0]: yield near, far, x

class Tab:
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
  def clone(i, rows=None):
    return Tab([i.names] + list(rows or []))
  def binned(i, rows=None):
    out = Tab([[c.txt.lower() for c in i.cols]])
    for row in rows if rows is not None else i.rows:
      out.add([c.bin(row[c.at]) for c in i.cols])
    return out
  def mid(i, cols=None):
    return {c.txt: c.mid() for c in (cols or i.cols)}
  def cut(i, rows, ys, Y=None, cols=None):
    Y = Y or (Sym if isinstance(ys[0], str) else Num)
    best, col1, v1 = 1e30, None, None
    for col in cols or i.x:
      xy = [(x, ys[k]) for k, r in enumerate(rows)
            if (x := r[col.at]) != "?"]
      for near, far, v in col.cut(xy, Y):
        if near.n >= the.leaf and far.n >= the.leaf:
          s = (near.div()*near.n + far.div()*far.n) / (near.n + far.n)
          if s < best: best, col1, v1 = s, col, v
    return col1, v1
  def ydist(i, row):
    d = sum(abs(c.norm(row[c.at]) - c.w)**the.p for c in i.y) / len(i.y)
    return d ** (1 / the.p)

class Tree:
  def __init__(i, tab, rows, ys, Y=None, cols=0, txt="", lvl=1):
    Y = Y or (Sym if isinstance(ys[0], str) else Num)
    i.rows, i.txt, i.lvl, i.kids, i.all = rows, txt, lvl, [], Y()
    for y in ys: i.all.add(y)
    i.mid = i.all.mid()
    if len(rows) >= 2 * the.leaf and lvl < the.depth:
      i.col, i.v = tab.cut(rows, ys, Y, pick(tab.x, cols))
      if i.col:
        a, b = [], []
        for k, r in enumerate(rows):
          (a if i.go(r) else b).append((r, ys[k]))
        if len(a) >= the.leaf and len(b) >= the.leaf:
          i.kids = [Tree(tab, [r for r, _ in t], [y for _, y in t], Y,
                         cols, f"{i.col.txt} {op} {i.v}", lvl + 1)
                    for t, op in zip((a, b), i.col.ops)]
  def go(i, row): return i.col.holds(row[i.col.at], i.v)
  def posts(i, row):
    n = i.leaf(row).all
    return ({k: v / n.n for k, v in n.has.items()}
            if hasattr(n, "has") else {})
  def guess(i, row): return i.leaf(row).mid
  def leaf(i, row):
    while i.kids: i = i.kids[0] if i.go(row) else i.kids[1]
    return i
  def dict(i):
    d = {"n": len(i.rows), "mid": i.mid}
    if i.txt: d["txt"] = i.txt
    if i.kids: d["left"],d["right"] = i.kids[0].dict(),i.kids[1].dict()
    return d

class Forest:
  def __init__(i, tab, rows=None, rounds=None):
    rows = tab.rows if rows is None else rows
    at, i.tab, i.all = tab.klass.at, tab, []
    c = max(1, floor(sqrt(len(tab.x))))
    for _ in range(rounds or the.rounds):
      rs = some(rows)
      i.all.append(Tree(tab, rs, [r[at] for r in rs], Sym, c))
  def votes(i, row):
    t, ks = {}, []
    for m in i.all:
      k = m.leaf(row).mid
      if k is not None:
        if k not in t: ks.append(k); t[k] = 0
        t[k] += 1
    return t, ks
  def posts(i, row):
    t, ks = i.votes(row)
    z = max(sum(t[k] for k in ks), 1)
    return {k: t[k] / z for k in ks}
  def guess(i, row):
    t, ks = i.votes(row)
    bk, b = None, -1
    for k in ks:
      if t[k] > b: b, bk = t[k], k
    return bk

def auc(t):
  ps = sorted(s for s, want in t if want)
  ns = sorted(s for s, want in t if not want)
  if not ps or not ns: return None
  j = k = tot = 0
  for x in ps:
    while j < len(ns) and ns[j] < x: j += 1; k = j
    while k < len(ns) and ns[k] == x: k += 1
    tot += j + (k - j) / 2
  return tot / (len(ps) * len(ns))

def aucline(cols):
  tot, w, mac = 0, 0, []
  for c in cols:
    a = auc(c)
    if a is not None:
      nk = sum(1 for _, want in c if want)
      tot, w = tot + nk * a, w + nk
      mac.append(a)
  if not mac: return 0.0, 0, 0.0
  return tot / w, len(mac), sum(mac) / len(mac)

def aucs(model, rows, at=None, ks=None):
  at = model.tab.klass.at if at is None else at
  ks = ks or sorted(model.tab.klass.has, key=str)
  post = [model.posts(r) for r in rows]
  return aucline([[(post[j].get(x, 0), r[at] == x)
                   for j, r in enumerate(rows)] for x in ks])

def near(a, b): return abs(a - b) < 1e-6

def ok(got, want):
  assert got == want or (
    isinstance(got, float) and near(got, want)), f"{got} != {want}"
  return got

def logfmt(_indent=0, **d):
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
  print(logfmt(guzzler=ok(t.ydist(t.rows[0]), 0.7863215821)))

def test_some():
  xs = list(range(10))
  print(logfmt(some=ok(len(some(xs)), 10), pick=ok(len(pick(xs, 3)), 3),
               all=ok(len(pick(xs)), 10)))
  assert pick(xs) is xs

def test_tree():
  t = Tab(the.train)
  node = Tree(t, t.rows, [t.ydist(r) for r in t.rows])
  print(logfmt(**node.dict()))
  assert node.kids and len(node.rows) == 398

def test_forest():
  t0 = time.perf_counter()
  train = Tab(the.cls)
  test = train if the.test == "None" else Tab(the.test)
  b = train.binned()
  f = Forest(b, b.rows)
  rows = train.binned(test.rows).rows
  at = b.klass.at
  acc = sum(f.guess(r) == r[at] for r in rows) / len(rows)
  a, nk, mac = aucs(f, rows)
  print(logfmt(trees=len(f.all), rows=len(rows), acc=acc,
               auc=a, klasses=nk, macroauc=mac,
               secs=time.perf_counter() - t0))
  assert 0 <= a <= 1 and nk > 1

def run(k):
  random.seed(the.seed)
  print(":" + k[5:]); globals()[k]()

def cli(argv):
  if not argv: return print(__doc__)
  for s in argv:
    if   (k := "test_" + s.lstrip("-")) in globals(): run(k)
    elif "=" in s: k, v = s.split("=", 1); setattr(the, k, value(v))
    else: sys.exit("? " + s)

if __name__ == "__main__": cli(sys.argv[1:])
