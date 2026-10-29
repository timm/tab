# sig.awk: lua in, "name TAB signature" out.  A return type is read
# from the source's own "--> type; prose".  A parameter's type comes
# from its name (the lexicon below), except that a method's first
# parameter is its receiver, and the value names v x a b take their
# kind from that receiver.  An unknown name is left bare.
# usage: gawk -f etc/sig.awk tab.lua
BEGIN { split("t rows lst names xs ys", a); for (k in a) ty[a[k]] = "list"
  split("row",          a); for (k in a) ty[a[k]] = "row"
  split("f y",          a); for (k in a) ty[a[k]] = "fun"
  split("s txt k how want got", a); for (k in a) ty[a[k]] = "str"
  split("n at",         a); for (k in a) ty[a[k]] = "int"
  split("file src",     a); for (k in a) ty[a[k]] = "file"
  split("col all",      a); for (k in a) ty[a[k]] = "NUM"
  split("tbl meta sub", a); for (k in a) ty[a[k]] = "TAB"
  split("v x a b",      a); for (k in a) ty[a[k]] = "atom" }

/^function[ \t]/ { d = ""; wrapped = 0                 # join a wrapped
  while (1) { c = $0                                   # declaration
    if (match(c, /-->/)) { r = substr(c, RSTART + 3); sub(/;.*/, "", r)
                           gsub(/^[ \t]+|[ \t]+$/, "", r)
                           c = substr(c, 1, RSTART - 1) }
    sub(/--.*/, "", c); d = d (d ? "\f" : "") c
    if (gsub(/\(/, "(", c) <= gsub(/\)/, ")", c) && d ~ /\(/) break
    if ((getline) <= 0) break; wrapped = 1 }
  emit(d, r); r = "" }

function emit(d, r,   nm, cls, p, q, par, np, i, t, s, lines) {
  nm = d; sub(/^function +/, "", nm); sub(/ *[(\f].*/, "", nm)
  cls = (nm ~ /\./) ? substr(nm, 1, index(nm, ".") - 1) : ""
  p = substr(d, index(d, "(") + 1); sub(/\).*/, "", p)
  if (index(p, "\f")) sub(/\f/, "|", p)       # wrapped: break = scratch
  else                sub(/   */, "|", p)     # inline:  2+ spaces
  gsub(/\f/, " ", p); split(p, q, "|"); s = ""
  np = split(q[1], par, / *, */)
  for (i = 1; i <= np; i++) { gsub(/[ \t]/, "", par[i])
    if (par[i] == "") continue
    t = (i == 1 && par[i] == "i") ? (cls ? cls : "inst") : ty[par[i]]
    if (t == "atom") t = (cls == "NUM") ? "num" :
                         (cls == "SYM" || cls == "BAG") ? "str" : "atom"
    s = s (s ? ", " : "") par[i] (t ? ":" t : "") }
  print nm "\t" (cls ? "." substr(nm, index(nm, ".") + 1) : nm) \
        "(" s ")" (r && r != "nil" ? " -> " r : "") }
