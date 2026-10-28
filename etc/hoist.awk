# hoist.awk: make tab.lua readable by pycco.  Three fixes, since
# pycco's idea of a comment is any line whose first non-blank is --
#   1. inside a [[ ]] string those dashes are data, not a comment,
#      so hide them; ,/html puts them back after pycco has run
#   2. a banner comment becomes a markdown heading (and stays a lua
#      comment, or pycco reads it as code).  Banners may open with a
#      form feed, the page break, so allow one
#   3. a comment trailing a function declaration moves above it,
#      where pycco reads it as that function's prose
# usage: awk -f etc/hoist.awk tab.lua
BEGIN { FS = "--" }
/\[\[/                { instr = 1 }
instr && /^[ \t]*--/  { sub(/--/, "%%DD%%") }
/\]\]/                { instr = 0 }
/^\f?-- -+ [a-z]/ { sub(/^\f?-- -+ /, "-- ## "); sub(/ *-+$/, "")
                    print; next }
/^function/ && NF > 1 { sub(/[ \t]+$/, "", $1)   # drop the alignment
                        print "--" $2 "\n" $1; next }
{ print }
