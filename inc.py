#!/usr/bin/env python3
# vim: set ts=2 sw=2 sts=2 et cc=65 :
"""inc.py: incremental nb + rmeans, scored prequentially.
(c) 2026 Tim Menzies <timm@ieee.org> MIT license.

usage: python3 inc.py [name=value | action | file.csv ...]

flags:
  bins=7     numeric columns get this many bins
  fmt=%.2f   how a fraction is printed
  m=2        m-estimate: prior weight for a thin bin
  p=2        minkowski coefficient
  warm=10    rows seen before a guess is scored
  test=None  held-out csv (None: train only)
  file=~/gits/moot/optimize/misc/auto93.csv

actions:
  go=nb      incremental naive Bayes
  go=rmeans  incremental range means"""

import sys, os, re
from math import exp, log
from types import SimpleNamespace as o

def value(x):
  x = x.strip()
  try: return int(x)
  except ValueError:
    try: return float(x)
    except ValueError: return x

the = o(**{k: value(v) for k, v in
           re.findall(r"\n\s+(\w+)=(\S+)", __doc__)})

class Sym:
  def __init__(i, txt="S", at=0):
    i.txt, i.at, i.n, i.has, i.cl = txt, at, 0, {}, 0
  def add(i, v, inc=1):
    if v != "?":
      i.n += inc
      c = i.has.get(v, 0)
      if c > 0: i.cl -= c * log(c)
      c += inc
      if c <= 0: i.has.pop(v, None)
      else: i.has[v], i.cl = c, i.cl + c * log(c)
    return v
  def div(i):
    return 0 if i.n<1 else max(0,log(i.n)-i.cl/i.n)/log(2)
  def mid(i):
    ks = sorted(i.has, key=str)
    return max(ks, key=lambda k: i.has[k]) if ks else None
  def norm(i, v): return v
  def bin(i, v): return v
  def nVals(i): return max(2, len(i.has))

class Num:
  def __init__(i, txt="N", at=0):
    i.txt, i.at, i.n, i.mu, i.m2 = txt, at, 0, 0, 0
    i.w = 0 if txt.endswith("-") else 1
  def add(i, v, inc=1):
    if v != "?":
      i.n += inc
      if i.n <= 0: i.n = i.mu = i.m2 = 0
      else:
        d = v - i.mu
        i.mu += inc * d / i.n
        i.m2 += inc * d * (v - i.mu)
    return v
  def div(i):
    return 0 if i.n < 2 else (max(i.m2, 0) / (i.n - 1)) ** .5
  def mid(i): return i.mu
  def norm(i, v):
    if v == "?": return v
    z = (v - i.mu) / (i.div() + 1e-32)
    return 1 / (1 + exp(-1.7 * max(-3, min(3, z))))
  def bin(i, v):
    if v == "?": return v
    return min(the.bins, 1 + int(the.bins * i.norm(v)))

def Col(txt, at):
  return (Num if txt[:1].isupper() else Sym)(txt, at)

class Tab:
  def __init__(i, src=()):
    i.rows, i.names, i.cols = [], [], []
    i.x, i.y, i.klass = [], [], None
    for row in src: i.add(row)
  def add(i, row):
    if not i.cols: return i.head(row)
    i.rows.append(row)
    for col in i.cols: col.add(row[col.at])
    return row
  def head(i, names):
    i.names = names
    for at, txt in enumerate(names):
      col = Col(txt, at)
      i.cols.append(col)
      if txt.endswith("X"): continue
      if txt[-1:] in "-+!":
        i.y.append(col)
        if txt.endswith("!"): i.klass = col
      else: i.x.append(col)
  def ydist(i, row):
    s = sum(abs(c.norm(row[c.at]) - c.w) ** the.p for c in i.y)
    return (s / len(i.y)) ** (1 / the.p)

def lines(file):
  path = os.path.expanduser(file)
  with open(path, encoding="utf-8-sig") as f:
    for line in f:
      s = line.strip()
      if s and s[0] != "#":
        yield [value(x) for x in s.split(",")]

def nvals(col):
  return the.bins if isinstance(col, Num) else col.nVals()

def update(i, row):
  for col in i.tab.cols: col.add(row[col.at])
  y = i.want(row)
  if y == "?": return
  i.caught(y)
  for col in i.tab.x:
    b = col.bin(row[col.at])
    if b != "?": i.add1(col, b, y)

def err(i, row):
  want, got = i.want(row), i.guess(row)
  if want == "?" or got is None: return "?"
  return i.loss(want, got)

class Nbi:
  def __init__(i, names):
    i.tab, i.subs = Tab([names]), {}
  def want(i, row): return row[i.tab.klass.at]
  def caught(i, y): pass
  def add1(i, col, b, k):
    if k not in i.subs:
      i.subs[k] = {c.at: Sym() for c in i.tab.x}
    i.subs[k][col.at].add(b)
  def like(i, k, sub, row):
    kl = i.tab.klass
    s = log((kl.has.get(k, 0) + the.m)
            / (kl.n + the.m * nvals(kl)))
    for col in i.tab.x:
      v = row[col.at]
      if v != "?":
        sym = sub[col.at]
        s += log((sym.has.get(col.bin(v), 0) + the.m)
                 / (sym.n + the.m * nvals(col)))
    return s
  def guess(i, row):
    if not i.subs: return None
    ks = sorted(i.subs, key=str)
    return max(ks, key=lambda k: i.like(k, i.subs[k], row))
  def loss(i, want, got): return 0 if want == got else 1

class Rmi:
  def __init__(i, names):
    i.tab, i.has = Tab([names]), {}
    y = i.tab.y
    i.goal = y[0] if len(y) == 1 and type(y[0]) is Num else None
    i.all = i.goal or Num()
  def want(i, row):
    return row[i.goal.at] if i.goal else i.tab.ydist(row)
  def caught(i, y):
    if not i.goal: i.all.add(y)
  def add1(i, col, b, y):
    t = i.has.setdefault(col.at, {})
    if b not in t: t[b] = Num()
    t[b].add(y)
  def like(i, col, row):
    bins = i.has.get(col.at)
    v = bins and bins.get(col.bin(row[col.at]))
    if not v: return None
    w = i.all.div() ** 2 - sum(u.n / i.all.n * u.div() ** 2
                               for u in bins.values())
    if w <= 0: return None
    return (v.n * v.mu + the.m * i.all.mu) / (v.n + the.m), w
  def guess(i, row):
    if i.all.n == 0: return None
    s = w = 0
    for col in i.tab.x:
      g = i.like(col, row)
      if g: s, w = s + g[1] * g[0], w + g[1]
    return s / w if w > 0 else i.all.mu
  def loss(i, want, got): return abs(got - want)

def learn(make):
  m, pre, post, n = None, Num(), None, 0
  for row in lines(the.file):
    n += 1
    if n == 1: m = make(row)
    else:
      if n > the.warm + 1: pre.add(err(m, row))
      update(m, row)
  if the.test and the.test != "None":
    post, n = Num(), 0
    for row in lines(the.test):
      n += 1
      if n > 1: post.add(err(m, row))
  return m, pre, post

def fmt(x):
  return str(int(x)) if x == int(x) else the.fmt % x

def report(what, pre, post):
  print(":prequential %s n=%s %s=%s"
        % (the.file, pre.n, what, fmt(pre.mu)))
  if post:
    print(":frozen %s n=%s %s=%s"
          % (the.test, post.n, what, fmt(post.mu)))

slow = {"nb":     lambda: report("err", *learn(Nbi)[1:]),
        "rmeans": lambda: report("mae", *learn(Rmi)[1:])}

def cli():
  for s in sys.argv[1:]:
    m = re.match(r"^([A-Za-z]\w*)=(.*)$", s)
    if m: setattr(the, m.group(1), value(m.group(2)))
    elif s in slow: slow[s]()
    else: the.file = s
  return the

if __name__ == "__main__":
  cli()
  if getattr(the, "go", None) in slow: slow[the.go]()
