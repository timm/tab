# sig.awk: lua in, "name TAB signature" out.  A return type is read from
# the source's own "--> type; prose".  A parameter's type comes from its
# name (the lexicon below), except that a method's first parameter is
# its receiver, and the value names v x a b take their kind from that
# receiver.  A name the lexicon does not know is left bare.
# usage: gawk -f etc/sig.awk tab.lua
BEGIN { lex("t rows lst names xs ys", "list"); lex("row", "row")
        lex("f y",             "fun");  lex("s txt k how want got", "str")
        lex("n at",            "int");  lex("file src",     "file")
        lex("col all",         "NUM");  lex("tbl meta sub", "TAB")
        lex("v x a b",         "atom") }

/^function[ \t]/ { d = ""; ret = ""      # a declaration may wrap onto a
  do { d = d (d ? "\f" : "") bare($0)    # second line, so keep reading
     } while (unclosed(d) && (getline) > 0)     # until its ( is closed
  print name(d) "\t" sig(d) }

function lex(names, t,   a, k) {         # every name in names is a t
  split(names, a, " "); for (k in a) ty[a[k]] = t }

function bare(s) {                       # the code, less its comment;
  if (match(s, /-->[ \t]*[^;]*/)) {      # "--> type" sets the return
    ret = substr(s, RSTART + 3, RLENGTH - 3); gsub(/[ \t]/, "", ret) }
  sub(/--.*/, "", s); return s }

function unclosed(s) { return gsub(/\(/, "(", s) > gsub(/\)/, ")", s) }

function name(d) { sub(/^function +/, "", d); sub(/[ (].*/, "", d)
                   return d }

function cls(nm) {                       # SAME.ok is SAME's;
                                         # map belongs to nobody
  return (nm ~ /\./) ? substr(nm, 1, index(nm, ".") - 1) : "" }

function real(d,   p) {                  # the real parameters: a line
  p = substr(d, index(d, "(") + 1)       # break, or a run of two or more
  sub(/\).*/, "", p)                     # spaces, starts the locals
  if (index(p, "\f")) sub(/\f.*/, "", p); else sub(/  .*/, "", p)
  gsub(/[ \t]/, "", p); return p }

function typed(p, at, c,   t) {          # one parameter, as name:type
  t = (at == 1 && p == "i") ? (c ? c : "inst") : ty[p]
  if (t == "atom" && c) t = (c == "NUM") ? "num" :
                           (c == "SYM" || c == "BAG") ? "str" : t
  return p (t ? ":" t : "") }

function sig(d,   nm, c, par, n, i, s) {
  nm = name(d); c = cls(nm); n = split(real(d), par, ",")
  for (i = 1; i <= n; i++)
    if (par[i] != "") s = s (s ? ", " : "") typed(par[i], i, c)
  return (c ? "." substr(nm, index(nm, ".") + 1) : nm) "(" s ")" \
         (ret && ret != "nil" ? " -> " ret : "") }
