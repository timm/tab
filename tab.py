#!/usr/bin/env python3
"""tab.py: minimal tab.lua -- just rmeans regression + naive bayes.
Columns: Uppercase=Num, else Sym; names ending X skip, -+! are goals,
! is the klass, - means minimize. (c) 2026 Tim Menzies, MIT."""
import sys, os
from math import exp, log
from types import SimpleNamespace as o

the = o(bins=7, depth=4, fmt="%.2f", leaf=8, m=2, p=2)

def thing(s):
  s = s.strip()
  try: return int(s)
  except ValueError:
    try: return float(s)
    except ValueError: return s

def logfmt(_indent=0, **d):                  # k=v ...; a dict value indents +1
  pad = "  " * _indent
  flat = " ".join(f"{k}={the.fmt % v if isinstance(v, float) else v}"
                  for k, v in sorted(d.items())
                  if not isinstance(v, dict))
  lines = [pad + flat] if flat else []
  for k, v in sorted(d.items()):
    if isinstance(v, dict):
      lines += [pad + k, logfmt(_indent + 1, **v)]
  return "\n".join(lines)

def csv(file):                               
  with open(os.path.expanduser(file), encoding="utf-8-sig") as f:    
    for line in f:                        
      s = line.strip()                   
      if s and s[0] != "#": yield [thing(v) for v in s.split(",")]

class Num:
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
  def holds(i, x, v): return x == "?" or x <= v
  def cuts(i, xy, Y):
    xy.sort(key=lambda p: p[0])
    near, far = Y(), Y()
    for _, y in xy: far.add(y)
    for j, (x, y) in enumerate(xy[:-1]):
      near.add(y); far.add(y, -1)
      if x != xy[j + 1][0]: yield near, far, x
  def norm(i, v):
    if v == "?": return v
    z = (v - i.mu) / (i.div() + 1e-32)
    return 1 / (1 + exp(-1.7 * max(-3, min(3, z))))
  def bin(i, v):
    return v if v == "?" else min(the.bins, 1 + int(the.bins * i.norm(v)))

class Sym:
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
  def holds(i, x, v): return x == "?" or x == v   # unknowns say yes, so
  def norm(i, v): return v                       # a cut loses no row
  def bin(i, v): return v
  def nVals(i): return max(2, len(i.has))
  def cuts(i, xy, Y):
    "One cut per symbol: that symbol, against all the rest."
    for v in sorted({x for x, _ in xy}, key=str):
      near, far = Y(), Y()
      for x, y in xy: (near if x == v else far).add(y)
      yield near, far, v

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
  def clone(i, rows=None):                 # a fresh Tab holding ROWS
    return Tab([i.names] + list(rows or []))
  def binned(i, rows=None):                # ROWS, discretized.  The
    out = Tab([[c.txt.lower() for c in i.cols]])   # lowercase names are
    for row in rows or []:                   # the point: a lowercase
      out.add([c.bin(row[c.at]) for c in i.cols])  # name is a Sym
    return out
  def cut(i, rows, ys, Y=None):
    Y = Y or (Sym if isinstance(ys[0], str) else Num)
    best, col1, v1 = 1e30, None, None
    for col in i.x:
      xy = [(x, ys[k]) for k, r in enumerate(rows)
            if (x := r[col.at]) != "?"]
      for near, far, v in col.cuts(xy, Y):
        if near.n >= the.leaf and far.n >= the.leaf:
          s = (near.div() * near.n + far.div() * far.n) / (near.n + far.n)
          if s < best: best, col1, v1 = s, col, v
    return col1, v1
  def ydist(i, row):
    d = sum(abs(c.norm(row[c.at]) - c.w) ** the.p for c in i.y) / len(i.y)
    return d ** (1 / the.p)

class Node:
  """A binary tree over ROWS, each split leaving the tightest ys behind.
  YS is one y per row, in row order; Y is read off it, so the same code
  grows a regression tree (sd) or a classification one (entropy)."""
  def __init__(i, tbl, rows, ys, Y=None, txt="", lvl=1):
    Y = Y or (Sym if isinstance(ys[0], str) else Num)
    i.rows, i.txt, i.lvl, i.kids, i.all = rows, txt, lvl, [], Y()
    for y in ys: i.all.add(y)
    i.mu = i.all.mid()                   # a mean, or a majority
    if len(rows) >= 2 * the.leaf and lvl < the.depth:
      i.col, i.v = tbl.cut(rows, ys, Y)
      if i.col:
        a, b = [], []
        for k, r in enumerate(rows):
          (a if i.go(r) else b).append((r, ys[k]))
        if len(a) >= the.leaf and len(b) >= the.leaf:  # else, a
          i.kids = [Node(tbl, [r for r, _ in t], [y for _, y in t], Y,
                         f"{i.col.txt} {op} {i.v}", lvl + 1)
                    for t, op in zip((a, b), i.col.ops)]    # bad cut
  def go(i, row): return i.col.holds(row[i.col.at], i.v)
  def leaf(i, row):
    "Walk ROW down to its leaf."
    while i.kids: i = i.kids[0] if i.go(row) else i.kids[1]
    return i
  def dict(i):
    "This node as nested dicts, for `logfmt` to draw."
    d = {"n": len(i.rows), "mu": i.mu}
    if i.txt: d["txt"] = i.txt
    if i.kids: d["left"], d["right"] = i.kids[0].dict(), i.kids[1].dict()
    return d

class Rmeans:
  "Regression: per-x-column bin means of y, m-estimated, weighed by variance."
  def __init__(i, tbl, rows, y):
    sub = tbl.clone(rows)
    i.all, i.cols, i.has = Num(), sub.x, {}
    for r in sub.rows: i.all.add(y(r))
    for col in sub.x:
      bins = {}
      for r in sub.rows: bins.setdefault(col.bin(r[col.at]), Num()).add(y(r))
      cut = i.all.div() ** 2 - sum(v.n / i.all.n * v.div() ** 2 for v in bins.values())
      i.has[col.at] = (bins, max(cut, 0))
  def guess(i, row):
    s = w = 0
    for col in i.cols:
      bins, wt = i.has[col.at]
      v = bins.get(col.bin(row[col.at]))
      if v and wt > 0:
        s += wt * (v.n * v.mu + the.m * i.all.mu) / (v.n + the.m); w += wt
    return s / w if w > 0 else i.all.mu

class Nb:
  "Naive Bayes: one sub-table per klass; guess the likeliest (binned data)."
  def __init__(i, tbl, rows):
    i.tbl, i.subs, i.n, i.nKlass = tbl, {}, len(rows), 0
    for r in rows:
      v = r[tbl.klass.at]
      if v not in i.subs: i.subs[v] = tbl.clone(); i.nKlass += 1
      i.subs[v].add(r)
  def like(i, sub, row):
    m = the.m
    L = log((len(sub.rows) + m) / (i.n + m * i.nKlass))
    for j, col1 in enumerate(sub.x):
      v = row[col1.at]
      if v != "?":
        L += log((col1.has.get(v, 0) + m) / (col1.n + m * i.tbl.x[j].nVals()))
    return L
  def guess(i, row):
    return max(i.subs, key=lambda k: i.like(i.subs[k], row))

if __name__ == "__main__":
  # naive bayes on a toy table (binned so every x is symbolic)
  t = Tab([["Age", "job", "klass!"],
           [20, "low", "no"], [22, "low", "no"], [25, "low", "no"],
           [30, "med", "no"], [60, "hi", "yes"], [62, "hi", "yes"],
           [65, "med", "yes"], [70, "hi", "yes"]])
  b = t.binned(t.rows)
  nb = Nb(b, b.rows)
  print("nb", nb.guess(b.rows[0]), nb.guess(b.rows[-1]))  # -> no yes
  # rmeans regression on a csv (target = distance-to-heaven over goals)
  if len(sys.argv) > 1:
    t = Tab(sys.argv[1])
    m = Rmeans(t, t.rows[:45], t.ydist)
    print("rmeans", round(m.all.mu, 3), round(m.guess(t.rows[0]), 3))
    # a regression tree over the same goal, as one logfmt record
    print(logfmt(**Node(t, t.rows, [t.ydist(r) for r in t.rows]).dict()))
