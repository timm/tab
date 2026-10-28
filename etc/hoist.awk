# hoist.awk: a comment trailing a function declaration moves above
# it, where pycco reads it as that function's prose.
# usage: awk -f etc/hoist.awk tab.lua
BEGIN { FS = "--" }
/^function/ && NF > 1 { sub(/[ \t]+$/, "", $1)   # drop the alignment
                        print "--" $2 "\n" $1; next }
{ print }
