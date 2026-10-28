# lit.awk: lua in, literate markdown out.  RS="" makes one record
# per blank-line separated paragraph and FS="\n" makes its lines the
# fields, so a paragraph is the unit of prose-or-code.  The leading
# -- lines of a paragraph are its prose; what follows is lua, and
# consecutive lua paragraphs share one fence.  A banner comment
# becomes a heading, and a comment trailing a function declaration
# becomes that function's prose.
# usage: gawk -f etc/lit.awk tab.lua
BEGIN { RS = ""; FS = "\n" }

function flush() {                       # close any open code fence
  if (code != "") { printf "```lua\n%s\n```\n\n", code; code = "" } }

function say(s) { flush(); printf "%s\n\n", s }

function add(s) { code = (code == "" ? s : code "\n" s) }

{ i = 1; txt = ""
  if (FNR == 1 && $1 ~ /^#!/) i = 2            # drop the shebang
  while (i <= NF && $i ~ /^\f?--( |$)/) {              # prose on top
    line = $i; sub(/^\f/, "", line); sub(/^-- ?/, "", line)
    if (line ~ /^-+ +[a-z]/) {                      # ---- bayes ----
      sub(/^-+ +/, "", line); sub(/ *-+$/, "", line); line = "## " line }
    txt = (txt == "" ? line : txt "\n" line); i++ }
  if (txt != "") say(txt)
  gap = (txt == "")                  # no prose: we are mid-fence, so
  if (i <= NF && $i ~ /^function/ && index($i, "--")) {   # keep the
    p = index($i, "--")                                   # blank line
    c = substr($i, p + 2); sub(/^ +/, "", c)
    d = substr($i, 1, p - 1); sub(/[ \t]+$/, "", d)
    say(c); add(d); i++; gap = 0 }
  if (gap && code != "") add("")
  for (; i <= NF; i++) add($i) }

END { flush() }
