# CLAUDE.md

tab is the library: `tab.yue`, the `tab.lua` it builds, `tab-eg.lua`,
and the `,/` scripts that run them. Keep it that way.

## tab.lua is generated. Do not hand-edit it.

`tab.yue` is the source. `,/build` compiles it:

    ,/build          # yue -c -s -o tab.lua tab.yue, then prints a sha1

Edit `tab.yue`, run `,/build`, commit both. An edit made directly to
`tab.lua` is lost the next time anyone builds.

It was hand-written until 2026-11-05. The yue port had caught up --
the two were measured byte-identical over 40 score files (8 sets x
`nb`, `hardeep`, `hardeepauc`, `treedeep`, `treedeepauc`) -- so the
only thing a second copy of one learner could still do was drift.
`-c` keeps the comments, which carry the argument and are most of
what a reader comes here for.

The build is deliberately not run by `,/sh` or `,/run`: a corpus that
recompiles per data set is a corpus that can change halfway through.
Build once, by hand, and pin a run to the sha1 it prints.

`tab-eg.lua`, `tree-eg.lua` and `tree.lua` are hand-written lua and
are not generated from anything.

## Everything else lives next door

Experiment results, score csvs, figures, sweeps, scratch files and
the notes on what has been tried belong in `../tab-dev`, the sibling
repo. Write them there, not here.

Read `../tab-dev/CLAUDE.md` before proposing an experiment. It lists
what has already been measured and rejected.
