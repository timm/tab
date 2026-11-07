#!/usr/bin/env python3
# vim: set ts=2 sw=2 sts=2 et cc=70 :
"""inc.py: incremental nb + rmeans, scored prequentially.
usage: python3 inc.py [name=value | nb | rmeans | file.csv ...]
(c) 2026 Tim Menzies <timm@ieee.org> MIT license."""

import sys, os, re
from bisect import insort
from math import exp, log, sqrt
from types import SimpleNamespace as o

the = o(bins=7, fmt="%.2f", m=2, p=2, warm=10, go="rmeans",
        few=128, start=4, stop=20, seed=1234567891,
        test="None", file="~/gits/moot/optimize/misc/auto93.csv")

def value(x):
  x = x.strip()
  try: return int(x)
  except ValueError:
    try: return float(x)
    except ValueError: return x

rng = None
def rint(j):
  global rng
  rng = (16807 * (rng or the.seed)) % 2147483647
  return 1 + int(j * rng / 2147483647)

def shuffle(u):
  u = u[:]
  for j in range(len(u) - 1, 0, -1):
    k = rint(j + 1) - 1
    u[j], u[k] = u[k], u[j]
  return u

def xdist(tab, r1, r2):
  d = 0
  for at in tab.x:
    a, b, col = r1[at], r2[at], tab.cols[at]
    if a == "?" and b == "?": d += 1
    elif type(col) is dict: d += 0 if a == b else 1
    else:
      a, b = norm(col, a), norm(col, b)
      if a == "?": a = 0 if b > .5 else 1
      elif b == "?": b = 0 if a > .5 else 1
      d += abs(a - b) ** the.p
  return (d / len(tab.x)) ** (1 / the.p)

def lines(file):
  with open(os.path.expanduser(file), encoding="utf-8-sig") as f:
    for line in f:
      s = line.strip()
      if s and s[0] != "#":
        yield [value(x) for x in s.split(",")]

# -------------------------------------------------------------------
def Col(txt):
  return (0, 0, 0, 0 if txt.endswith("-") else 1) \
         if txt[:1].isupper() else {}

def add(col, v, inc=1):
  if v == "?": return col
  if type(col) is dict:
    col[v] = col.get(v, 0) + inc
    if col[v] <= 0: del col[v]
    return col
  n, mu, m2, w = col
  n += inc
  if n <= 0: return (0, 0, 0, w)
  d = v - mu
  mu += inc * d / n
  return (n, mu, m2 + inc * d * (v - mu), w)

def n(col):
  return sum(col.values()) if type(col) is dict else col[0]

def div(num):
  return 0 if num[0] < 2 else sqrt(max(num[2], 0) / (num[0] - 1))

def norm(col, v):
  if v == "?" or type(col) is dict: return v
  z = (v - col[1]) / (div(col) + 1e-32)
  return 1 / (1 + exp(-1.7 * max(-3, min(3, z))))

def bin(col, v):
  if v == "?" or type(col) is dict: return v
  return min(the.bins, 1 + int(the.bins * norm(col, v)))

def mid(col):
  return (max(sorted(col, key=str), key=col.get, default=None)
          if type(col) is dict else col[1])

def nvals(col):
  return max(2, len(col)) if type(col) is dict else the.bins

# -------------------------------------------------------------------
class Tab:
  def __init__(tab, names, rows=()):
    tab.names, tab.rows = names, []
    tab.cols, tab.x, tab.y, tab.klass = [], [], [], None
    for at, txt in enumerate(names):
      tab.cols.append(Col(txt))
      if txt.endswith("X"): continue
      if txt[-1:] in "-+!":
        tab.y.append(at)
        if txt.endswith("!"): tab.klass = at
      else: tab.x.append(at)
    for row in rows: addRow(tab, row)
  def ydist(tab, row):
    c = tab.cols
    s = sum(abs(norm(c[at], row[at]) - c[at][3]) ** the.p
            for at in tab.y)
    return (s / len(tab.y)) ** (1 / the.p)

def addRow(tab, row, inc=1, keep=True):
  if keep and inc > 0: tab.rows.append(row)
  for at in range(len(tab.cols)):
    tab.cols[at] = add(tab.cols[at], row[at], inc)
  return row

def update(model, row):
  t = model.tab
  for at in range(len(t.cols)):
    t.cols[at] = add(t.cols[at], row[at])
  y = model.want(row)
  if y == "?": return
  model.caught(y)
  for at in t.x:
    b = bin(t.cols[at], row[at])
    if b != "?": model.add1(at, b, y)

def err(model, row):
  want, got = model.want(row), model.guess(row)
  if want == "?" or got is None: return "?"
  return model.loss(want, got)

# -------------------------------------------------------------------
def learn(make):
  m, pre, post, j = None, (0, 0, 0, 1), None, 0
  for row in lines(the.file):
    j += 1
    if j == 1: m = make(row)
    else:
      if j > the.warm + 1: pre = add(pre, err(m, row))
      update(m, row)
  if the.test and the.test != "None":
    post, j = (0, 0, 0, 1), 0
    for row in lines(the.test):
      j += 1
      if j > 1: post = add(post, err(m, row))
  return m, pre, post

class Nbi:
  def __init__(nb, names):
    nb.tab, nb.subs = Tab(names), {}
  def want(nb, row): return row[nb.tab.klass]
  def caught(nb, y): pass
  def add1(nb, at, b, k):
    if k not in nb.subs: nb.subs[k] = {j: {} for j in nb.tab.x}
    add(nb.subs[k][at], b)
  def like(nb, k, sub, row):
    kl = nb.tab.cols[nb.tab.klass]
    s = log((kl.get(k, 0) + the.m) / (n(kl) + the.m * nvals(kl)))
    for at in nb.tab.x:
      v = row[at]
      if v != "?":
        col = nb.tab.cols[at]
        s += log((sub[at].get(bin(col, v), 0) + the.m)
                 / (n(sub[at]) + the.m * nvals(col)))
    return s
  def guess(nb, row):
    if not nb.subs: return None
    ks = sorted(nb.subs, key=str)
    return max(ks, key=lambda k: nb.like(k, nb.subs[k], row))
  def loss(nb, want, got): return 0 if want == got else 1

class Rmi:
  def __init__(rm, names):
    rm.tab, rm.has = Tab(names), {}
    y = rm.tab.y
    rm.goal = y[0] if len(y) == 1 and \
             type(rm.tab.cols[y[0]]) is tuple else None
    rm.all = (0, 0, 0, 1) if rm.goal is None else None
  def want(rm, row):
    return row[rm.goal] if rm.goal is not None else rm.tab.ydist(row)
  def caught(rm, y):
    if rm.goal is None: rm.all = add(rm.all, y)
  def tot(rm):
    return rm.tab.cols[rm.goal] if rm.goal is not None else rm.all
  def add1(rm, at, b, y):
    t = rm.has.setdefault(at, {})
    t[b] = add(t.get(b, (0, 0, 0, 1)), y)
  def like(rm, at, row):
    bins, tot = rm.has.get(at), rm.tot()
    v = bins and bins.get(bin(rm.tab.cols[at], row[at]))
    if not v: return None
    w = div(tot) ** 2 - sum(u[0] / tot[0] * div(u) ** 2
                            for u in bins.values())
    if w <= 0: return None
    return (v[0] * v[1] + the.m * tot[1]) / (v[0] + the.m), w
  def guess(rm, row):
    tot = rm.tot()
    if tot[0] == 0: return None
    s = w = 0
    for at in rm.tab.x:
      g = rm.like(at, row)
      if g: s, w = s + g[1] * g[0], w + g[1]
    return s / w if w > 0 else tot[1]
  def loss(rm, want, got): return abs(got - want)

# -------------------------------------------------------------------
def acquire(tab, cap=None):
  cap = cap or the.stop
  todo = shuffle(tab.rows)[:the.few]
  both = Tab(tab.names, [todo.pop() for _ in range(the.start)])
  both.rows.sort(key=both.ydist)
  n, kid = int(the.start ** .5), lambda rows: Tab(tab.names, rows)
  best, rest = kid(both.rows[:n]), kid(both.rows[n:])
  while todo and len(both.rows) < cap:
    rmid = [mid(c) for c in rest.cols]
    bmid = [mid(c) for c in best.cols]
    todo.sort(key=lambda z: xdist(tab, z, rmid) - xdist(tab, z, bmid))
    addRow(best, addRow(both, todo.pop()))
    best.rows.sort(key=both.ydist)
    if len(best.rows) > len(both.rows) ** .5:
      addRow(rest, addRow(best, best.rows.pop(), -1, keep=0))
  return both.rows

def acq():
  global rng
  rng = the.seed
  src = list(lines(the.file))
  tab = Tab(src[0], src[1:])
  def ys(rows):
    u = sorted(tab.ydist(r) for r in rows)
    return "%s/%s" % (fmt(u[0]), fmt(sum(u) / len(u)))
  got = acquire(tab)
  print(":acquire %s n=%s best=%s rand=%s all=%s"
        % (the.file, len(got), ys(got),
           ys(shuffle(tab.rows)[:len(got)]), ys(tab.rows)))

def fmt(x):
  return str(int(x)) if x == int(x) else the.fmt % x

def report(what, pre, post):
  print(":prequential %s n=%s %s=%s"
        % (the.file, pre[0], what, fmt(pre[1])))
  if post:
    print(":frozen %s n=%s %s=%s"
          % (the.test, post[0], what, fmt(post[1])))

slow = {"nb":      lambda: report("err", *learn(Nbi)[1:]),
        "rmeans":  lambda: report("mae", *learn(Rmi)[1:]),
        "acquire": acq}

def cli():
  for s in sys.argv[1:]:
    m = re.match(r"^([A-Za-z]\w*)=(.*)$", s)
    if m: setattr(the, m.group(1), value(m.group(2)))
    elif s in slow: slow[s]()
    else: the.file = s
  return the

if __name__ == "__main__":
  cli()
  if the.go in slow: slow[the.go]()
