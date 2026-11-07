local the, slow, help, floor, exp, sqrt, log, abs, min, max, TAB, NUM, SYM, NBI, RMI, Col, Sym, Num, Tab, lines, eat, nvals, update, err, Nbi, Rmi, learn, report, new, values, cli, map, sum, same, lt, sort, order, o, print, fmt, main
the, slow = { }, { }
help = [[inc.yue: incremental nb + rmeans, scored prequentially.
(c) 2026 Tim Menzies <timm@ieee.org> MIT license.

usage: yue inc.yue [name=value | action | file.csv ...]

flags:
  bins=7           numeric columns get this many bins
  fmt=%.2f         how a fraction is printed
  m=2              m-estimate: prior weight for a thin bin
  p=2              minkowski coefficient
  warm=10          rows seen before a guess is scored
  test=None        held-out csv (None: train only)
  file=~/gits/moot/optimize/misc/auto93.csv

actions:
  go=nb            incremental naive Bayes
  go=rmeans        incremental range means]]
floor, exp, sqrt, log = math.floor, math.exp, math.sqrt, math.log
abs, min, max = math.abs, math.min, math.max
TAB, NUM, SYM, NBI, RMI = { }, { }, { }, { }, { }
Col = function(txt, at)
	return (txt:find("^%u") and Num or Sym)(txt, at)
end
Sym = function(txt, at)
	return new(SYM, {
		txt = txt or "S",
		at = at or 0,
		n = 0,
		has = { },
		cl = 0
	})
end
SYM.add = function(self, v, inc)
	if not (v == "?") then
		inc = inc or 1
		self.n = self.n + inc
		local c = self.has[v] or 0
		if c > 0 then
			self.cl = self.cl - (c * log(c))
		end
		c = c + inc
		if c <= 0 then
			self.has[v] = nil
		else
			self.has[v] = c
			self.cl = self.cl + (c * log(c))
		end
	end
	return v
end
SYM.div = function(self)
	return self.n < 1 and 0 or max(0, log(self.n) - self.cl / self.n) / log(2)
end
SYM.mid = function(self)
	local ks = { }
	for v in pairs(self.has) do
		ks[#ks + 1] = v
	end
	sort(ks, function(x, y)
		return tostring(x) < tostring(y)
	end)
	local bk
	local b = -1
	for _, v in order(ks) do
		if self.has[v] > b then
			b, bk = self.has[v], v
		end
	end
	return bk
end
SYM.norm = function(self, v)
	return v
end
SYM.bin = function(self, v)
	return v
end
SYM.nVals = function(self)
	return max(2, sum(self.has, function()
		return 1
	end))
end
Num = function(txt, at)
	return new(NUM, {
		txt = txt or "N",
		at = at or 0,
		n = 0,
		mu = 0,
		m2 = 0,
		w = ((txt or ""):find("%-$") and 0 or 1)
	})
end
NUM.add = function(self, v, inc)
	if not (v == "?") then
		inc = inc or 1
		self.n = self.n + inc
		if self.n <= 0 then
			self.n, self.mu, self.m2 = 0, 0, 0
		else
			local d = v - self.mu
			self.mu = self.mu + (inc * d / self.n)
			self.m2 = self.m2 + (inc * d * (v - self.mu))
		end
	end
	return v
end
NUM.div = function(self)
	return self.n < 2 and 0 or sqrt(max(self.m2, 0) / (self.n - 1))
end
NUM.mid = function(self)
	return self.mu
end
NUM.bin = function(self, v)
	if v == "?" then
		return v
	end
	local b = 1 + floor(the.bins * self:norm(v))
	return b > the.bins and the.bins or b
end
NUM.norm = function(self, v)
	if v == "?" then
		return v
	end
	local z = (v - self.mu) / (self:div() + 1e-32)
	z = z > 3 and 3 or (z < -3 and -3 or z)
	return 1 / (1 + exp(-1.7 * z))
end
Tab = function(src)
	local i = new(TAB, {
		rows = { },
		names = { },
		cols = { },
		x = { },
		y = { }
	})
	for _, row in order((src or { })) do
		i:add(row)
	end
	return i
end
TAB.add = function(self, row)
	if #self.cols == 0 then
		return self:head(row)
	end
	self.rows[#self.rows + 1] = row
	for _, col in order(self.cols) do
		col:add(row[col.at])
	end
	return row
end
TAB.head = function(self, names)
	self.names = names
	for at, txt in order(names) do
		local col = Col(txt, at)
		self.cols[#self.cols + 1] = col
		if not txt:find("X$") then
			if txt:find("[-+!]$") then
				self.y[#self.y + 1] = col
				if txt:find("!$") then
					self.klass = col
				end
			else
				self.x[#self.x + 1] = col
			end
		end
	end
	return nil
end
TAB.ydist = function(self, row)
	local fn
	fn = function(col)
		return abs(col:norm(row[col.at]) - col.w) ^ the.p
	end
	return (sum(self.y, fn) / #self.y) ^ (1 / the.p)
end
lines = function(file)
	local path = file:gsub("^~", os.getenv("HOME") or "~")
	local f = io.lines(path)
	return function()
		for line in f do
			local s = line:match("^%s*(.-)%s*$")
			if s ~= "" and s:sub(1, 1) ~= "#" then
				return values(s)
			end
		end
	end
end
eat = function(i, row)
	local _list_0 = i.cols
	for _index_0 = 1, #_list_0 do
		local col = _list_0[_index_0]
		col:add(row[col.at])
	end
end
nvals = function(col)
	if col.it == NUM then
		return the.bins
	end
	return col:nVals()
end
update = function(i, row)
	eat(i.tab, row)
	local y = i:want(row)
	if y == "?" then
		return
	end
	i:caught(y)
	local _list_0 = i.tab.x
	for _index_0 = 1, #_list_0 do
		local col = _list_0[_index_0]
		local b = col:bin(row[col.at])
		if b ~= "?" then
			i:add1(col, b, y)
		end
	end
end
err = function(i, row)
	local want, got = i:want(row), i:guess(row)
	if want == "?" or got == nil then
		return "?"
	end
	return i:loss(want, got)
end
Nbi = function(names)
	return new(NBI, {
		tab = Tab({
			names
		}),
		subs = { }
	})
end
NBI.want = function(self, row)
	return row[self.tab.klass.at]
end
NBI.caught = function(self, y) end
NBI.add1 = function(self, col, b, k)
	local sub = self.subs[k]
	if not sub then
		sub = { }
		local _list_0 = self.tab.x
		for _index_0 = 1, #_list_0 do
			local c = _list_0[_index_0]
			sub[c.at] = Sym()
		end
		self.subs[k] = sub
	end
	return sub[col.at]:add(b)
end
NBI.like = function(self, k, sub, row)
	local kl = self.tab.klass
	local s = log(((kl.has[k] or 0) + the.m) / (kl.n + the.m * nvals(kl)))
	local _list_0 = self.tab.x
	for _index_0 = 1, #_list_0 do
		local col = _list_0[_index_0]
		local v = row[col.at]
		if v ~= "?" then
			local b, sym = col:bin(v), sub[col.at]
			s = s + log(((sym.has[b] or 0) + the.m) / (sym.n + the.m * nvals(col)))
		end
	end
	return s
end
NBI.klasses = function(self)
	local ks = { }
	for k in pairs(self.subs) do
		ks[#ks + 1] = k
	end
	return sort(ks, function(a, b)
		return tostring(a) < tostring(b)
	end)
end
NBI.guess = function(self, row)
	if not next(self.subs) then
		return nil
	end
	local bk
	local b = -math.huge
	for _, k in order(self:klasses()) do
		local v = self:like(k, self.subs[k], row)
		if v > b then
			b, bk = v, k
		end
	end
	return bk
end
NBI.loss = function(self, want, got)
	return want == got and 0 or 1
end
Rmi = function(names)
	local i = new(RMI, {
		tab = Tab({
			names
		}),
		has = { }
	})
	i.goal = #i.tab.y == 1 and i.tab.y[1].it == NUM and i.tab.y[1]
	i.all = i.goal or Num()
	return i
end
RMI.want = function(self, row)
	if self.goal then
		return row[self.goal.at]
	end
	return self.tab:ydist(row)
end
RMI.caught = function(self, y)
	if not self.goal then
		return self.all:add(y)
	end
end
RMI.add1 = function(self, col, b, y)
	local t = self.has[col.at] or { }
	self.has[col.at] = t
	t[b] = t[b] or Num()
	return t[b]:add(y)
end
RMI.like = function(self, col, row)
	local bins = self.has[col.at]
	local v = bins and bins[col:bin(row[col.at])]
	if not v then
		return
	end
	local w = self.all:div() ^ 2 - sum(bins, function(u)
		return u.n / self.all.n * u:div() ^ 2
	end)
	if w > 0 then
		return (v.n * v.mu + the.m * self.all.mu) / (v.n + the.m), w
	end
end
RMI.guess = function(self, row)
	if self.all.n == 0 then
		return nil
	end
	local s, w = 0, 0
	local _list_0 = self.tab.x
	for _index_0 = 1, #_list_0 do
		local col = _list_0[_index_0]
		local g, wt = self:like(col, row)
		if g then
			s, w = s + wt * g, w + wt
		end
	end
	return w > 0 and s / w or self.all.mu
end
RMI.loss = function(self, want, got)
	return abs(got - want)
end
learn = function(make)
	local m, post
	local n, pre = 0, Num()
	for row in lines(the.file) do
		n = n + 1
		if n == 1 then
			m = make(row)
		else
			if n > the.warm + 1 then
				pre:add(err(m, row))
			end
			update(m, row)
		end
	end
	if the.test and the.test ~= "None" then
		post, n = Num(), 0
		for row in lines(the.test) do
			n = n + 1
			if n > 1 then
				post:add(err(m, row))
			end
		end
	end
	return m, pre, post
end
report = function(what, pre, post)
	print(fmt(":prequential %s n=%s %s=%s", the.file, pre.n, what, o(pre.mu)))
	if post then
		return print(fmt(":frozen %s n=%s %s=%s", the.test, post.n, what, o(post.mu)))
	end
end
slow.nb = function()
	return report("err", select(2, learn(Nbi)))
end
slow.rmeans = function()
	return report("mae", select(2, learn(Rmi)))
end
new = function(meta, i)
	meta.__index, meta.it, meta.__tostring = meta, meta, o
	return setmetatable(i, meta)
end
values = function(s)
	local u = { }
	for s1 in (s .. ","):gmatch("(.-),") do
		local v = s1:match("^%s*(.-)%s*$")
		u[#u + 1] = tonumber(v) or v
	end
	return u
end
cli = function()
	for _, s in order(arg) do
		local k, v = s:match("^(%a%w*)=(.*)$")
		if k then
			the[k] = values(v)[1]
		elseif slow[s] then
			slow[s]()
		else
			the.file = s
		end
	end
	return the
end
map = function(t, fn)
	local u = { }
	for k, v in ipairs(t) do
		u[#u + 1] = fn(v, k)
	end
	return u
end
sum = function(t, fn)
	local n = 0
	for k, v in pairs(t) do
		n = n + fn(v, k)
	end
	return n
end
same = function(x)
	return x
end
lt = function(a, b)
	return a < b
end
sort = function(t, fn)
	if fn and type(fn) ~= "function" then
		local k = fn
		fn = function(a, b)
			return a[k] < b[k]
		end
	end
	table.sort(t, fn)
	return t
end
order = function(t, fn)
	if not fn then
		return ipairs(t)
	end
	return ipairs(sort(map(t, same), fn))
end
o = function(x)
	if type(x) ~= "table" then
		if type(x) ~= "number" then
			return tostring(x)
		end
		return tostring(x == floor(x) and floor(x) or the.fmt:format(x))
	end
	local u = { }
	if #x > 0 then
		for _, v in ipairs(x) do
			u[#u + 1] = o(v)
		end
	else
		for k, v in pairs(x) do
			if k ~= "it" and type(v) ~= "function" then
				u[#u + 1] = o(k) .. "=" .. o(v)
			end
		end
	end
	return "{" .. table.concat((#x > 0 and u or sort(u, lt)), " ") .. "}"
end
print = function(...)
	local out = { }
	for j = 1, select("#", ...) do
		out[j] = o((select(j, ...)))
	end
	io.write(table.concat(out, "\t"), "\n")
	return nil
end
fmt = function(s, ...)
	return s:format(...)
end
for k, v in help:gmatch("\n%s+(%a+)=(%S+)") do
	the[k] = values(v)[1]
end
main = (arg and arg[0]) or ""
if main:find("inc%.yue$") or main:find("inc%.lua$") then
	cli()
	if the.go and slow[the.go] then
		slow[the.go]()
	end
end
return setmetatable({
	the = the,
	help = help,
	slow = slow,
	TAB = TAB,
	NUM = NUM,
	SYM = SYM,
	NBI = NBI,
	RMI = RMI,
	Col = Col,
	Sym = Sym,
	Num = Num,
	Tab = Tab,
	Nbi = Nbi,
	Rmi = Rmi,
	lines = lines,
	eat = eat,
	nvals = nvals,
	update = update,
	err = err,
	learn = learn,
	report = report,
	new = new,
	values = values,
	cli = cli,
	map = map,
	sum = sum,
	same = same,
	lt = lt,
	sort = sort,
	order = order,
	o = o,
	print = print,
	fmt = fmt
}, {
	__index = _G
})
