local abs, exp, floor, huge, log, max, min, sqrt, NUM, the, value, lt, sort, sortBy, sum, rint, shuffle, take, lines, Num, isNum, Col, add, n, div, norm, bin, argmax, mid, mids, nvals, Tab, addRow, ydist, xdist, update, err, learn, Nbi, Rmi, acquire, acq, fmt, report, slow, cli, main
abs, exp, floor, huge = math.abs, math.exp, math.floor, math.huge
log, max, min, sqrt = math.log, math.max, math.min, math.sqrt
NUM = { }
the = {
	bins = 7,
	fmt = "%.2f",
	m = 2,
	p = 2,
	warm = 10,
	go = "rmeans",
	few = 128,
	start = 4,
	stop = 20,
	seed = 1234567891,
	rng = 1234567891,
	test = "None",
	file = "~/gits/moot/optimize/misc/auto93.csv"
}
value = function(s)
	return tonumber(s) or s:match("^%s*(.-)%s*$")
end
lt = function(a, b)
	return a < b
end
sort = function(u, fn)
	return table.sort(u, fn) or u
end
sortBy = function(u, fn)
	local key, was = { }, { }
	for at, v in ipairs(u) do
		key[v], was[v] = fn(v), at
	end
	return sort(u, function(a, b)
		return key[a] == key[b] and was[a] < was[b] or key[a] < key[b]
	end)
end
sum = function(t, fn)
	local s = 0
	for k, v in pairs(t) do
		s = s + fn(v, k)
	end
	return s
end
rint = function(j)
	the.rng = (16807 * the.rng) % 2147483647
	return 1 + floor(j * the.rng / 2147483647)
end
shuffle = function(u)
	do
		local _accum_0 = { }
		local _len_0 = 1
		for _, v in ipairs(u) do
			_accum_0[_len_0] = v
			_len_0 = _len_0 + 1
		end
		u = _accum_0
	end
	for j = #u, 2, -1 do
		local k = rint(j)
		u[j], u[k] = u[k], u[j]
	end
	return u
end
take = function(u, j1, j2)
	local _accum_0 = { }
	local _len_0 = 1
	for j, v in ipairs(u) do
		if j >= j1 and j <= j2 then
			_accum_0[_len_0] = v
			_len_0 = _len_0 + 1
		end
	end
	return _accum_0
end
lines = function(file)
	local path = file:gsub("^~", os.getenv("HOME") or "~")
	local f = io.lines(path)
	return function()
		for line in f do
			local s = line:match("^%s*(.-)%s*$")
			if s ~= "" and s:sub(1, 1) ~= "#" then
				local _accum_0 = { }
				local _len_0 = 1
				for v in (s .. ","):gmatch("(.-),") do
					_accum_0[_len_0] = value(v)
					_len_0 = _len_0 + 1
				end
				return _accum_0
			end
		end
	end
end
Num = function(w)
	return setmetatable({
		0,
		0,
		0,
		w or 1
	}, NUM)
end
isNum = function(col)
	return getmetatable(col) == NUM
end
Col = function(txt)
	return txt:find("^%u") and Num(txt:find("%-$") and 0 or 1) or { }
end
add = function(col, v, inc)
	if inc == nil then
		inc = 1
	end
	if v == "?" then
		return col
	end
	if not isNum(col) then
		local c = (col[v] or 0) + inc
		col[v] = c > 0 and c or nil
		return col
	end
	if col[1] + inc <= 0 then
		col[1], col[2], col[3] = 0, 0, 0
	else
		local _update_0 = 1
		col[_update_0] = col[_update_0] + inc
		local d = v - col[2]
		local _update_1 = 2
		col[_update_1] = col[_update_1] + (inc * d / col[1])
		local _update_2 = 3
		col[_update_2] = col[_update_2] + (inc * d * (v - col[2]))
	end
	return col
end
n = function(col)
	return isNum(col) and col[1] or sum(col, function(v)
		return v
	end)
end
div = function(num)
	return num[1] < 2 and 0 or sqrt(max(num[3], 0) / (num[1] - 1))
end
norm = function(col, v)
	if v == "?" or not isNum(col) then
		return v
	end
	local z = (v - col[2]) / (div(col) + 1e-32)
	return 1 / (1 + exp(-1.7 * max(-3, min(3, z))))
end
bin = function(col, v)
	if v == "?" or not isNum(col) then
		return v
	end
	return min(the.bins, 1 + floor(the.bins * norm(col, v)))
end
local _anon_func_0 = function(pairs, t)
	local _accum_0 = { }
	local _len_0 = 1
	for k in pairs(t) do
		_accum_0[_len_0] = k
		_len_0 = _len_0 + 1
	end
	return _accum_0
end
argmax = function(t, fn)
	local out
	local b = -huge
	for _, k in ipairs(sort(_anon_func_0(pairs, t), function(x, y)
		return tostring(x) < tostring(y)
	end)) do
		local v = fn(k)
		if v > b then
			b, out = v, k
		end
	end
	return out
end
mid = function(col)
	return isNum(col) and col[2] or argmax(col, function(k)
		return col[k]
	end)
end
mids = function(tab)
	local u = { }
	for at = 1, #tab.cols do
		u[at] = mid(tab.cols[at])
	end
	return u
end
nvals = function(col)
	return isNum(col) and the.bins or max(2, sum(col, function()
		return 1
	end))
end
Tab = function(names, rows)
	local tab = {
		names = names,
		rows = { },
		cols = { },
		x = { },
		y = { }
	}
	for at, txt in ipairs(names) do
		tab.cols[at] = Col(txt)
		if txt:find("X$") then
			goto _continue_0
		end
		local u = txt:find("[-+!]$") and tab.y or tab.x
		u[#u + 1] = at
		if txt:find("!$") then
			tab.klass = at
		end
		::_continue_0::
	end
	for _, row in ipairs(rows or { }) do
		addRow(tab, row)
	end
	return tab
end
addRow = function(tab, row, inc, keep)
	if inc == nil then
		inc = 1
	end
	if keep == nil then
		keep = true
	end
	if keep and inc > 0 then
		tab.rows[#tab.rows + 1] = row
	end
	for at = 1, #tab.cols do
		tab.cols[at] = add(tab.cols[at], row[at], inc)
	end
	return row
end
ydist = function(tab, row)
	local c = tab.cols
	local f
	f = function(at)
		return abs(norm(c[at], row[at]) - c[at][4]) ^ the.p
	end
	return (sum(tab.y, f) / #tab.y) ^ (1 / the.p)
end
xdist = function(tab, r1, r2)
	local d = 0
	for _, at in ipairs(tab.x) do
		local a, b, col = r1[at], r2[at], tab.cols[at]
		if a == "?" and b == "?" then
			d = d + 1
		elseif not isNum(col) then
			d = d + (a == b and 0 or 1)
		else
			a, b = norm(col, a), norm(col, b)
			if a == "?" then
				a = b > .5 and 0 or 1
			end
			if b == "?" then
				b = a > .5 and 0 or 1
			end
			d = d + (abs(a - b) ^ the.p)
		end
	end
	return (d / #tab.x) ^ (1 / the.p)
end
update = function(model, row)
	local t = model.tab
	for at = 1, #t.cols do
		t.cols[at] = add(t.cols[at], row[at])
	end
	local y = model.want(row)
	if y == "?" then
		return
	end
	model.caught(y)
	for _, at in ipairs(t.x) do
		local b = bin(t.cols[at], row[at])
		if b ~= "?" then
			model.add1(at, b, y)
		end
	end
end
err = function(model, row)
	local want, got = model.want(row), model.guess(row)
	if want == "?" or got == nil then
		return "?"
	end
	return model.loss(want, got)
end
learn = function(make)
	local m, post
	local pre, j = Num(), 0
	for row in lines(the.file) do
		j = j + 1
		if j == 1 then
			m = make(row)
		else
			if j > the.warm + 1 then
				pre = add(pre, err(m, row))
			end
			update(m, row)
		end
	end
	if the.test and the.test ~= "None" then
		post, j = Num(), 0
		for row in lines(the.test) do
			j = j + 1
			if j > 1 then
				post = add(post, err(m, row))
			end
		end
	end
	return m, pre, post
end
local _anon_func_1 = function(ipairs, nb)
	local _tbl_0 = { }
	for _, j in ipairs(nb.tab.x) do
		_tbl_0[j] = { }
	end
	return _tbl_0
end
Nbi = function(names)
	local nb = {
		tab = Tab(names),
		subs = { }
	}
	nb.want = function(row)
		return row[nb.tab.klass]
	end
	nb.caught = function() end
	nb.add1 = function(at, b, k)
		local _obj_0 = nb.subs
		_obj_0[k] = _obj_0[k] or _anon_func_1(ipairs, nb)
		return add(nb.subs[k][at], b)
	end
	nb.like = function(k, sub, row)
		local kl = nb.tab.cols[nb.tab.klass]
		local s = log(((kl[k] or 0) + the.m) / (n(kl) + the.m * nvals(kl)))
		for _, at in ipairs(nb.tab.x) do
			local v = row[at]
			if v ~= "?" then
				local col = nb.tab.cols[at]
				s = s + log(((sub[at][bin(col, v)] or 0) + the.m) / (n(sub[at]) + the.m * nvals(col)))
			end
		end
		return s
	end
	nb.guess = function(row)
		return next(nb.subs) and argmax(nb.subs, function(k)
			return nb.like(k, nb.subs[k], row)
		end) or nil
	end
	nb.loss = function(want, got)
		return want == got and 0 or 1
	end
	return nb
end
Rmi = function(names)
	local rm = {
		tab = Tab(names),
		has = { }
	}
	local ys = rm.tab.y
	rm.goal = #ys == 1 and isNum(rm.tab.cols[ys[1]]) and ys[1] or nil
	rm.all = not rm.goal and Num() or nil
	rm.want = function(row)
		return rm.goal and row[rm.goal] or ydist(rm.tab, row)
	end
	rm.caught = function(y)
		if not rm.goal then
			rm.all = add(rm.all, y)
		end
	end
	rm.tot = function()
		return rm.goal and rm.tab.cols[rm.goal] or rm.all
	end
	rm.add1 = function(at, b, y)
		local t = rm.has[at] or { }
		rm.has[at] = t
		t[b] = add((t[b] or Num()), y)
	end
	rm.like = function(at, row)
		local bins, tot = rm.has[at], rm.tot()
		local v = bins and bins[bin(rm.tab.cols[at], row[at])]
		if not v then
			return
		end
		local w = div(tot) ^ 2 - sum(bins, function(u)
			return u[1] / tot[1] * div(u) ^ 2
		end)
		if w > 0 then
			return (v[1] * v[2] + the.m * tot[2]) / (v[1] + the.m), w
		end
	end
	rm.guess = function(row)
		local tot = rm.tot()
		if tot[1] == 0 then
			return nil
		end
		local s, w = 0, 0
		for _, at in ipairs(rm.tab.x) do
			local g, wt = rm.like(at, row)
			if g then
				s, w = s + wt * g, w + wt
			end
		end
		return w > 0 and s / w or tot[2]
	end
	rm.loss = function(want, got)
		return abs(got - want)
	end
	return rm
end
local _anon_func_2 = function(table, the, todo)
	local _accum_0 = { }
	local _len_0 = 1
	for _ = 1, the.start do
		_accum_0[_len_0] = table.remove(todo)
		_len_0 = _len_0 + 1
	end
	return _accum_0
end
acquire = function(tab, cap)
	cap = cap or the.stop
	local todo = take(shuffle(tab.rows), 1, the.few)
	local kid
	kid = function(rows)
		return Tab(tab.names, rows)
	end
	local both = kid(_anon_func_2(table, the, todo))
	sortBy(both.rows, function(r)
		return ydist(both, r)
	end)
	local k = floor(the.start ^ .5)
	local best = kid(take(both.rows, 1, k))
	local rest = kid(take(both.rows, k + 1, huge))
	while #todo > 0 and #both.rows < cap do
		local rmid, bmid = mids(rest), mids(best)
		sortBy(todo, function(z)
			return xdist(tab, z, rmid) - xdist(tab, z, bmid)
		end)
		addRow(best, addRow(both, table.remove(todo)))
		sortBy(best.rows, function(r)
			return ydist(both, r)
		end)
		if #best.rows > (#both.rows) ^ .5 then
			addRow(rest, addRow(best, table.remove(best.rows), -1, false))
		end
	end
	return both.rows
end
local _anon_func_3 = function(ipairs, rows, tab, ydist)
	local _accum_0 = { }
	local _len_0 = 1
	for _, r in ipairs(rows) do
		_accum_0[_len_0] = ydist(tab, r)
		_len_0 = _len_0 + 1
	end
	return _accum_0
end
acq = function()
	local src
	do
		local _accum_0 = { }
		local _len_0 = 1
		for row in lines(the.file) do
			_accum_0[_len_0] = row
			_len_0 = _len_0 + 1
		end
		src = _accum_0
	end
	local tab = Tab(src[1], take(src, 2, huge))
	local ys
	ys = function(rows)
		local u = sort(_anon_func_3(ipairs, rows, tab, ydist), lt)
		local s = 0
		for _, v in ipairs(u) do
			s = s + v
		end
		return ("%s/%s"):format(fmt(u[1]), fmt(s / #u))
	end
	local got = acquire(tab)
	local rand = ys(take(shuffle(tab.rows), 1, #got))
	return print((":acquire %s n=%s best=%s rand=%s all=%s"):format(the.file, #got, ys(got), rand, ys(tab.rows)))
end
fmt = function(x)
	return x == floor(x) and tostring(floor(x)) or the.fmt:format(x)
end
report = function(what, pre, post)
	print((":prequential %s n=%s %s=%s"):format(the.file, pre[1], what, fmt(pre[2])))
	if post then
		return print((":frozen %s n=%s %s=%s"):format(the.test, post[1], what, fmt(post[2])))
	end
end
slow = {
	nb = function()
		return report("err", select(2, learn(Nbi)))
	end,
	rmeans = function()
		return report("mae", select(2, learn(Rmi)))
	end,
	acquire = acq
}
cli = function()
	for _, s in ipairs(arg or { }) do
		local k, v = s:match("^(%a[%w_]*)=(.*)$")
		if k then
			the[k] = value(v)
		elseif slow[s] then
			the.rng = the.seed
			slow[s]()
		else
			the.file = s
		end
	end
	return the
end
main = (arg and arg[0]) or ""
if main:find("inc%.yue$") or main:find("inc%.lua$") then
	the.rng = cli().seed
	if slow[the.go] then
		slow[the.go]()
	end
end
return setmetatable({
	the = the,
	slow = slow,
	NUM = NUM,
	Num = Num,
	isNum = isNum,
	Col = Col,
	add = add,
	n = n,
	div = div,
	norm = norm,
	bin = bin,
	mid = mid,
	mids = mids,
	nvals = nvals,
	argmax = argmax,
	Tab = Tab,
	addRow = addRow,
	ydist = ydist,
	xdist = xdist,
	update = update,
	err = err,
	learn = learn,
	Nbi = Nbi,
	Rmi = Rmi,
	acquire = acquire,
	acq = acq,
	value = value,
	lt = lt,
	sort = sort,
	sortBy = sortBy,
	sum = sum,
	rint = rint,
	shuffle = shuffle,
	take = take,
	lines = lines,
	fmt = fmt,
	report = report,
	cli = cli
}, {
	__index = _G
})
