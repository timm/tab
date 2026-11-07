#!/usr/bin/env python3
# vim: set ts=2 sw=2 sts=2 et cc=70 :
"""inc.py: incremental nb + rmeans, scored prequentially.
usage: python3 inc.py [name=value | nb | rmeans | file.csv ...]
(c) 2026 Tim Menzies <timm@ieee.org> MIT license."""

import sys, os, re
from math import exp, log
from types import SimpleNamespace as o

the = o(bins=7, fmt="%.2f", m=2, p=2, warm=10, go="rmeans",
        test="None", file="~/gits/moot/optimize/misc/auto93.csv")

def value(x):
  x = x.strip()
  try: return int(x)
  except ValueError:
    try: return float(x)
    except ValueError: return x

def Col(txt):
  return {} if txt[:1].islower() else \
         (0, 0, 0, 0 if txt.endswith("-") else 1)

def add(c, v, inc=1):
  if v == "?": return c
  if type(c) is dict:
    c[v] = c.get(v, 0) + inc
    if c[v] <= 0: del c[v]
    return c
  n, mu, m2, w = c
  n += inc
  if n <= 0: return (0, 0, 0, w)
  d = v - mu
  mu += inc * d / n
  return (n, mu, m2 + inc * d * (v - mu), w)

def n(c):
  return sum(c.values()) if type(c) is dict else c[0]

def div(c):
  return 0 if c[0] < 2 else (max(c[2], 0) / (c[0] - 1)) ** .5

def norm(c, v):
  if v == "?" or type(c) is dict: return v
  z = (v - c[1]) / (div(c) + 1e-32)
  return 1 / (1 + exp(-1.7 * max(-3, min(3, z))))

def bin(c, v):
  if v == "?" or type(c) is dict: return v
  return min(the.bins, 1 + int(the.bins * norm(c, v)))

def nvals(c):
  return max(2, len(c)) if type(c) is dict else the.bins

class Tab:
  def __init__(i, names):
    i.cols, i.x, i.y, i.klass = [], [], [], None
    for at, txt in enumerate(names):
      i.cols.append(Col(txt))
      if txt.endswith("X"): continue
      if txt[-1:] in "-+!":
        i.y.append(at)
        if txt.endswith("!"): i.klass = at
      else: i.x.append(at)
  def ydist(i, row):
    s = sum(abs(norm(i.cols[at], row[at]) - i.cols[at][3]) ** the.p
            for at in i.y)
    return (s / len(i.y)) ** (1 / the.p)

def lines(file):
  with open(os.path.expanduser(file), encoding="utf-8-sig") as f:
    for line in f:
      s = line.strip()
      if s and s[0] != "#":
        yield [value(x) for x in s.split(",")]

def update(i, row):
  t = i.tab
  for at in range(len(t.cols)):
    t.cols[at] = add(t.cols[at], row[at])
  y = i.want(row)
  if y == "?": return
  i.caught(y)
  for at in t.x:
    b = bin(t.cols[at], row[at])
    if b != "?": i.add1(at, b, y)

def err(i, row):
  want, got = i.want(row), i.guess(row)
  if want == "?" or got is None: return "?"
  return i.loss(want, got)

class Nbi:
  def __init__(i, names):
    i.tab, i.subs = Tab(names), {}
  def want(i, row): return row[i.tab.klass]
  def caught(i, y): pass
  def add1(i, at, b, k):
    if k not in i.subs: i.subs[k] = {j: {} for j in i.tab.x}
    add(i.subs[k][at], b)
  def like(i, k, sub, row):
    kl = i.tab.cols[i.tab.klass]
    s = log((kl.get(k, 0) + the.m) / (n(kl) + the.m * nvals(kl)))
    for at in i.tab.x:
      v = row[at]
      if v != "?":
        c = i.tab.cols[at]
        s += log((sub[at].get(bin(c, v), 0) + the.m)
                 / (n(sub[at]) + the.m * nvals(c)))
    return s
  def guess(i, row):
    if not i.subs: return None
    ks = sorted(i.subs, key=str)
    return max(ks, key=lambda k: i.like(k, i.subs[k], row))
  def loss(i, want, got): return 0 if want == got else 1

class Rmi:
  def __init__(i, names):
    i.tab, i.has = Tab(names), {}
    y = i.tab.y
    i.goal = y[0] if len(y) == 1 and \
             type(i.tab.cols[y[0]]) is tuple else None
    i.all = (0, 0, 0, 1) if i.goal is None else None
  def want(i, row):
    return row[i.goal] if i.goal is not None else i.tab.ydist(row)
  def caught(i, y):
    if i.goal is None: i.all = add(i.all, y)
  def tot(i):
    return i.tab.cols[i.goal] if i.goal is not None else i.all
  def add1(i, at, b, y):
    t = i.has.setdefault(at, {})
    t[b] = add(t.get(b, (0, 0, 0, 1)), y)
  def like(i, at, row):
    bins, all = i.has.get(at), i.tot()
    v = bins and bins.get(bin(i.tab.cols[at], row[at]))
    if not v: return None
    w = div(all) ** 2 - sum(u[0] / all[0] * div(u) ** 2
                            for u in bins.values())
    if w <= 0: return None
    return (v[0] * v[1] + the.m * all[1]) / (v[0] + the.m), w
  def guess(i, row):
    all = i.tot()
    if all[0] == 0: return None
    s = w = 0
    for at in i.tab.x:
      g = i.like(at, row)
      if g: s, w = s + g[1] * g[0], w + g[1]
    return s / w if w > 0 else all[1]
  def loss(i, want, got): return abs(got - want)

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

def fmt(x):
  return str(int(x)) if x == int(x) else the.fmt % x

def report(what, pre, post):
  print(":prequential %s n=%s %s=%s"
        % (the.file, pre[0], what, fmt(pre[1])))
  if post:
    print(":frozen %s n=%s %s=%s"
          % (the.test, post[0], what, fmt(post[1])))

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
  if the.go in slow: slow[the.go]()
