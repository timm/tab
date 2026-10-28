# prompt.bash: the work shell's prompt -- where you are, and which
# branch.  Mid-rebase git leaves HEAD detached, so the branch name
# has to come out of the rebase directory; that is also the state
# worth shouting about, hence the REBASE/MERGE tag.
__tab_branch() {                   # " branch", or nothing if no repo
  local d b
  d=$(git rev-parse --git-dir 2>/dev/null) || return
  if   [ -d "$d/rebase-merge" ]
  then b="$(sed 's|refs/heads/||' "$d/rebase-merge/head-name") REBASE"
  elif [ -d "$d/rebase-apply" ]
  then b="$(sed 's|refs/heads/||' "$d/rebase-apply/head-name") REBASE"
  else b=$(git symbolic-ref --short -q HEAD) ||
       b=$(git rev-parse --short HEAD 2>/dev/null) || return
       [ -f "$d/MERGE_HEAD" ] && b="$b MERGE"
  fi
  printf ' %s' "$b"
}
PS1='\[\e[36m\]$(basename "$(dirname "$PWD")")/\W\[\e[0m\]'
PS1=$PS1'\[\e[32m\]$(__tab_branch)\[\e[0m\] ᐅ '
