#!/usr/bin/env eco

local file = require 'eco.file'
local time = require 'eco.time'
local sys = require 'eco.sys'
local eco = require 'eco'
local test = require 'test'

local function shell_ok(cmd)
	local ok, why, code = os.execute(cmd)

	if type(ok) == 'number' then
		return ok == 0
	end

	return ok == true and why == 'exit' and code == 0
end

local function rm_tree(root)
	if not file.access(root) then
		return
	end

	local entries = {}

	file.walk(root, function(path, _, info)
		entries[#entries + 1] = {
			path = path,
			type = info.type
		}
	end)

	table.sort(entries, function(a, b)
		return #a.path > #b.path
	end)

	for _, entry in ipairs(entries) do
		os.remove(entry.path)
	end

	os.remove(root)
end

local root = string.format('/tmp/eco-file-test-%d-%d', sys.getpid(), math.floor(time.now() * 1000))

rm_tree(root)
assert(file.mkdir(root, file.S_IRWXU))

-- readfile/writefile + basic path/stat helpers.
do
	local p = root .. '/basic.txt'
	local link = root .. '/basic.link'

	assert(file.writefile(p, 'hello\nworld\n'))
	assert(file.writefile(p, 'tail\n', true))
	assert(file.readfile(p) == 'hello\nworld\ntail\n')
	assert(file.readfile(p, '*l') == 'hello')

	assert(file.access(p))
	assert(file.access(p, 'r'))

	local st, err = file.stat(p)
	assert(st, err)
	assert(st.type == 'REG')
	assert(st.size == #'hello\nworld\ntail\n')

	local total_kb, avail_kb, used_kb = file.statvfs(root)
	assert(type(total_kb) == 'number')
	assert(type(avail_kb) == 'number')
	assert(type(used_kb) == 'number')
	assert(total_kb >= 0 and avail_kb >= 0 and used_kb >= 0)

	assert(file.dirname(root .. '/a/b/c') == root .. '/a/b')
	assert(file.basename(root .. '/a/b/c') == 'c')

	assert(shell_ok(string.format('ln -sfn %q %q', p, link)), 'failed to create symlink')
	local target, target_err = file.readlink(link)
	assert(target == p, target_err)

	local fh, fh_err = file.open(p, file.O_RDONLY)
	assert(fh, fh_err)
	fh:close()
end

-- dir() + walk() traversal semantics.
do
	local tree = root .. '/tree'

	assert(file.mkdir(tree, file.S_IRWXU))
	assert(file.mkdir(tree .. '/a', file.S_IRWXU))
	assert(file.mkdir(tree .. '/b', file.S_IRWXU))
	assert(file.writefile(tree .. '/a/one.txt', '1'))
	assert(file.writefile(tree .. '/b/two.txt', '2'))

	local names = {}

	for name, info in file.dir(tree) do
		names[name] = info.type
	end

	assert(names.a == 'DIR')
	assert(names.b == 'DIR')

	local visited = {}

	file.walk(tree, function(path, name)
		visited[path] = true

		if name == 'b' then
			return file.SKIP
		end
	end)

	assert(visited[tree .. '/a'])
	assert(visited[tree .. '/a/one.txt'])
	assert(visited[tree .. '/b'])
	assert(not visited[tree .. '/b/two.txt'], 'walk should skip descendants when callback returns file.SKIP')

	local count = 0

	file.walk(tree, function()
		count = count + 1
		return false
	end)

	assert(count == 1, 'walk should terminate immediately when callback returns false')

	test.expect_error(function()
		for _ in file.dir(root .. '/not-exist') do
		end
	end, 'dir should throw on opendir failure')

	local dangling = tree .. '/dangling'
	assert(shell_ok(string.format('ln -sfn %q %q', tree .. '/missing-target', dangling)), 'failed to create dangling symlink')

	local seen_lnk = false
	for name, info in file.dir(tree) do
		if name == 'dangling' then
			seen_lnk = true
			assert(info.type == 'LNK', 'dangling symlink should be reported as LNK')
		end
	end

	assert(seen_lnk, 'dangling symlink entry should be visible in dir iteration')

	test.expect_error(function()
		file.walk(false, function() end)
	end, 'walk should validate root argument type')
end

test.run_case_async('file object read/write/lseek/stat', function()
	local p = root .. '/rw.txt'
	local f, err = file.open(p,
			file.O_RDWR | file.O_CREAT | file.O_TRUNC,
			file.S_IRUSR | file.S_IWUSR)

	assert(f, err)

	local n
	n, err = f:write('abcdef\nline2\n', 0.2)
	assert(n == 13, err)

	local st
	st, err = f:stat()
	assert(st, err)
	assert(st.type == 'REG')
	assert(st.size == 13)

	local off = f:lseek(0, file.SEEK_SET)
	assert(off == 0)

	local data
	data, err = f:read(6, 0.2)
	assert(data == 'abcdef', err)

	data, err = f:read(1, 0.2)
	assert(data == '\n', err)

	data, err = f:read('*l', 0.2)
	assert(data == 'line2', err)

	off, err = f:lseek(0, file.SEEK_SET)
	assert(off == 0, err)

	local chunk, found = f:readuntil('cd', 0.2)
	assert(chunk == 'ab')
	assert(found == true)

	data, err = f:readfull(4, 0.2)
	assert(data == 'ef\nl', err)

	assert(f:flock(file.LOCK_EX, 0.2))
	assert(f:flock(file.LOCK_UN, 0.2))

	f:close()
	f:close()
end)

test.run_case_async('inotify add/wait/del', function()
	local watch_dir = root .. '/watch'
	local created = watch_dir .. '/x.txt'

	assert(file.mkdir(watch_dir, file.S_IRWXU))

	local w, err = file.inotify()
	assert(w, err)

	local wd
	wd, err = w:add(watch_dir, file.IN_CREATE | file.IN_CLOSE_WRITE)
	assert(wd, err)

	eco.run(function()
		eco.sleep(0.01)
		assert(file.writefile(created, 'hello'))
	end)

	local deadline = sys.uptime() + 1.0
	local got_event = false

	while sys.uptime() < deadline do
		local ev
		ev, err = w:wait(0.2)

		if not ev then
			assert(err == 'timeout', err)
		else
			if ev.name == created and ((ev.mask & file.IN_CREATE) > 0 or (ev.mask & file.IN_CLOSE_WRITE) > 0) then
				got_event = true
				break
			end
		end
	end

	assert(got_event, 'inotify should report create/close_write event for created file')

	assert(w:del(wd))
	assert(file.writefile(watch_dir .. '/after-del.txt', 'noevent'))

	local ev
	ev, err = w:wait(0.1)
	assert(ev == nil and err == 'timeout', 'watcher should not receive events after del()')

	w:close()
	w:close()
end)

-- GC regression: file/inotify objects should close fd in __gc.
do
	local weak = setmetatable({}, { __mode = 'v' })
	local fd_file
	local fd_watch

	do
		local f = assert(file.open(root .. '/gc-file.txt',
				file.O_RDWR | file.O_CREAT | file.O_TRUNC,
				file.S_IRUSR | file.S_IWUSR))

		fd_file = f.fd
		weak.f = f
	end

	do
		local w = assert(file.inotify())

		fd_watch = w.fd
		weak.w = w
	end

	test.full_gc()

	assert(weak.f == nil and weak.w == nil, 'file and inotify objects should be collectible')

	local ok, err = file.close(fd_file)
	assert(ok == nil and err, 'file fd should already be closed by __gc')

	ok, err = file.close(fd_watch)
	assert(ok == nil and err, 'inotify fd should already be closed by __gc')
end

rm_tree(root)

print('file tests passed')
