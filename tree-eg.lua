#!/usr/bin/env lua
-- vim: set ts=2 sw=2 sts=2 et cc=75 :
-- tree-eg.lua: the tree as a classifier.  Grown on klass entropy
-- rather than ydist, so `Sym` collects the scores and `div` is
-- entropy.  Two ways to answer at a leaf -- the klass counts already
-- sitting there, or a naive Bayes fitted inside it -- against naive
-- Bayes over the whole table.  The question is whether splitting
-- first buys anything a single model does not already have.
-- usage: luajit tree-eg.lua go=treemaj file=f.csv
package.path = (arg[0]:match"^(.*)/" or ".") .. "/?.lua;" .. package.path
require "tree"                      -- first: its usage sets defaults
local tab = require "tab-eg"        -- last: its stats and scoring
if setfenv then setfenv(1, tab) end
local _ENV = tab

usage = [[
flags:
  file=~/gits/moot/classify/diabetes.csv   a table with a klass
]]
for k, v in usage:gmatch"\n%s+(%a+)=(%S+)" do the[k] = values(v)[1] end

-- Return a tree over `tr`'s binned rows, split to leave the least
-- klass entropy behind, with that binned table beside it.  Binning
-- is what a leaf's naive Bayes wants anyway, so both arms see the
-- same columns and only the answer at the leaf differs.
--
-- Depth grows with the klass count.  A tree of depth d holds at most
-- 2^(d-1) leaves, so a majority vote over 8 leaves cannot name 19
-- klasses -- it would be reporting the shape of the tree, not what
-- the tree learned.  Take the smallest depth that can name them all,
-- then one level of slack, and never less than `the.depth`.
function ktree(tr,    trb,k,d,was,i) --> TREE, TAB
  trb  = tr:clone(tr.rows, "bin")
  k, d = trb.klass:nVals(), 2
  while 2^(d-1) < k do d = d + 1 end
  was, the.depth = the.depth, max(the.depth, d + 1)
  i    = Tree(trb, trb.rows,
              function(row) return row[trb.klass.at] end, Sym)
  the.depth = was
  return i, trb end

-- ---- the two answers -------------------------------------------------
function majGuess(i,row) return i:pick(row).mid end      --> atom
function majPosts(i,row) return i:posts(row) end         --> dict
function nbGuess(i,row)  return i:pick(row):nb():guess(row) end --> atom
function nbPosts(i,row)  return i:pick(row):nb():posts(row) end --> dict

-- ---- scoring ---------------------------------------------------------
-- Return macro acc, pd, pf and d2h of `how`'s guesses over `te`.
function treeScore(tr,te,how,    i,trb,bag,col) --> str
  i, trb  = ktree(tr)
  bag, col = Bag(), trb.klass
  for _, row in order(tr:clone(te.rows, "bin").rows) do
    bag:tally(row[col.at], how(i, row)) end
  return Acc:format(bag:score()) end

-- Return every klass's one-against-the-rest auc, averaged by klass
-- frequency and again equally, with the klass count between them.
-- Same shape as `bayesAuc`, so the numbers sit in the same column of
-- the same chart.
function treeAuc(tr,te,how,    i,trb,col,rows,post,t,cols) --> str
  i, trb = ktree(tr)
  col    = trb.klass
  rows   = tr:clone(te.rows, "bin").rows
  post   = {}
  for _, row in order(rows) do post[row] = how(i, row) end
  cols = {}
  for _, x in order(keys(col.has)) do       -- sorted, not `pairs`
    t = {}
    for _, row in order(rows) do
      t[#t + 1] = {post[row][x] or 0, row[col.at] == x} end
    cols[#cols + 1] = t end
  return aucline(cols) end

-- ---- rigs ------------------------------------------------------------
function arm(who,how,score,what)    -- one cached run of one arm
  return function()
    print(scored(the.file, who,
                 function(tr,te) return score(tr, te, how) end,
                 what)) end end

slow.treemaj    = arm("treemaj",    majGuess, treeScore, AccCols)
slow.treenb     = arm("treenb",     nbGuess,  treeScore, AccCols)
slow.treemajauc = arm("treemajauc", majPosts, treeAuc,   AucCols)
slow.treenbauc  = arm("treenbauc",  nbPosts,  treeAuc,   AucCols)

if (arg and arg[0] or ""):find"tree%-eg%.lua$" then
  the = cli()                       -- read late: every usage block
  ok, err = pcall(slow[the.go] or fast[the.go]   -- has had its say
                  or function() error("no go=" .. tostring(the.go)) end)
  if not ok then
    io.stderr:write(the.file, ": ", tostring(err), "\n") end end
return _ENV
