# lit.awk: lua in, literate markdown out.  RS="" makes one record
# per blank-line separated paragraph and FS="\n" makes its lines the
# fields, so a paragraph is the unit of prose-or-code.  The leading
# -- lines of a paragraph are its prose; what follows is lua, and
# consecutive lua paragraphs share one fence.  A banner comment
# becomes a heading, and a comment trailing a function declaration
# becomes that function's prose.
# usage: gawk -f etc/lit.awk tab.lua
BEGIN { FS = "\n"                        # $SIGS: etc/sig.awk's output,
  while ((getline g < ENVIRON["SIGS"]) > 0) {   # "name TAB signature"
    p = index(g, "\t")                   # name TAB derived signature
    if (p) sig[substr(g, 1, p-1)] = substr(g, p+1) }
  RS = "" }                              # paragraph mode, AFTER getline

function flush() {                       # close any open code fence
  if (code != "") { printf "```lua\n%s\n```\n\n", code; code = "" } }

function say(s) { flush(); printf "%s\n\n", s }

function add(s) { code = (code == "" ? s : code "\n" s) }

function dot(s) { return s ~ /[.!?:]$/ ? s : s "." }   # one full stop

{ i = 1; txt = ""; head = ""
  if (FNR == 1 && $1 ~ /^#!/) i = 2            # drop the shebang
  while (i <= NF && $i ~ /^\f?--( |$)/) {              # prose on top
    line = $(i++); sub(/^\f/, "", line); sub(/^-- ?/, "", line)
    if (line ~ /vim:.*set /) continue            # the editor modeline
    if (line ~ /^-+ +[a-z]/) {                      # ---- bayes ----
      sub(/^-+ +/, "", line); sub(/ *-+$/, "", line)
      head = "## " line; continue }       # a heading stands on its own
    txt = (txt == "" ? line : txt "\n" line) }
  if (head != "") say(head)
  gap = (txt == "" && head == "")    # no prose: we are mid-fence, so
  if (i <= NF && $i ~ /^function/ && index($i, "--")) {   # keep the
    p = index($i, "--")                                   # blank line
    c = substr($i, p + 2); sub(/^ +/, "", c)
    sub(/^> *[A-Za-z_]+;? */, "", c)   # "--> type" shows as the sig
    d = substr($i, 1, p - 1); sub(/[ \t]+$/, "", d)
    n = d; sub(/^function +/, "", n); sub(/ *\(.*/, "", n)
    if (n in sig) c = "`" sig[n] "`" (c == "" ? "" : " " c)
    c = c (c == "" || txt == "" ? txt : " " txt)
    if (c != "") say(dot(c))
    txt = ""; add(d); i++; gap = 0 }           # sig first, then prose
  if (txt != "") say(txt)
  if (gap && code != "") add("")
  for (; i <= NF; i++) add($i) }

END { flush() }
