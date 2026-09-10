-- "Most recently created" views.
--
-- Two entry points:
--   * M.picker() — snacks picker over all non-git-ignored files under the
--     repo root, sorted by creation time (birthtime), newest first.
--   * M.toggle() — oil view of the directory you're working in sorted by
--     creation time, with a created-at column and git-ignored files hidden.
--     Bound to gC inside oil; same key toggles back to the name sort.
local M = {}

-- when true, oil sorts by birthtime and hides git-ignored entries
M.active = false

local DEFAULT_COLUMNS = { "icon" }
local RECENT_COLUMNS = { "icon", { "birthtime", format = "%Y-%m-%d %H:%M" } }
local DEFAULT_SORT = { { "type", "asc" }, { "name", "asc" } }
local RECENT_SORT = { { "birthtime", "desc" } }

-- dir -> set of git-ignored entry names in that dir
local ignored_cache = {}

local function git_ignored(dir)
	local cached = ignored_cache[dir]
	if cached then
		return cached
	end
	local names = {}
	local result = vim.system({
		"git",
		"ls-files",
		"--ignored",
		"--exclude-standard",
		"--others",
		"--directory",
		"--no-empty-directory",
	}, { cwd = dir, text = true }):wait()
	if result.code == 0 and result.stdout then
		for line in vim.gsplit(result.stdout, "\n", { plain = true, trimempty = true }) do
			names[(line:gsub("/$", ""))] = true
		end
	end
	ignored_cache[dir] = names
	return names
end

-- wired into oil's view_options.is_always_hidden; only filters in recent mode
function M.is_always_hidden(name, bufnr)
	if not M.active then
		return false
	end
	if name == ".git" then
		return true
	end
	local ok, dir = pcall(require("oil").get_current_dir, bufnr)
	if not ok or not dir then
		return false
	end
	return git_ignored(dir)[name] == true
end

function M.toggle()
	local oil = require("oil")
	M.active = not M.active
	ignored_cache = {}
	if M.active then
		oil.set_columns(RECENT_COLUMNS)
		oil.set_sort(RECENT_SORT)
	else
		oil.set_columns(DEFAULT_COLUMNS)
		oil.set_sort(DEFAULT_SORT)
	end
	vim.notify("Oil: sorted by " .. (M.active and "most recently created" or "name"), vim.log.levels.INFO)
end

local function fmt_age(secs)
	if secs < 3600 then
		return ("%dm"):format(math.max(1, math.floor(secs / 60)))
	elseif secs < 86400 then
		return ("%dh"):format(math.floor(secs / 3600))
	elseif secs < 86400 * 30 then
		return ("%dd"):format(math.floor(secs / 86400))
	else
		return ("%dmo"):format(math.floor(secs / (86400 * 30)))
	end
end

-- Snacks picker: all non-git-ignored files under the repo root (or cwd),
-- newest creation time first. Birthtime via stat %W; falls back to mtime on
-- filesystems without birthtime.
function M.picker(limit)
	limit = limit or 2000
	local root = vim.fs.root(0, ".git") or vim.uv.cwd()
	local cmd = [[fd --type f --hidden --exclude .git --print0 | xargs -0 -r stat --printf '%W\t%Y\t%n\n']]
	local result = vim.system({ "sh", "-c", cmd }, { cwd = root, text = true }):wait()
	if result.code ~= 0 or not result.stdout or result.stdout == "" then
		vim.notify("recent-created: fd/stat failed under " .. root, vim.log.levels.ERROR)
		return
	end

	local files = {}
	for line in vim.gsplit(result.stdout, "\n", { plain = true, trimempty = true }) do
		local btime, mtime, name = line:match("^(%-?%d+)\t(%d+)\t(.+)$")
		if name then
			name = name:gsub("^%./", "")
			local t = tonumber(btime)
			if not t or t <= 0 then
				t = tonumber(mtime)
			end
			table.insert(files, { time = t, name = name })
		end
	end
	table.sort(files, function(a, b)
		return a.time > b.time
	end)

	local now = os.time()
	local items = {}
	for i = 1, math.min(limit, #files) do
		local f = files[i]
		table.insert(items, {
			file = root .. "/" .. f.name,
			text = f.name,
			created = f.time,
		})
	end

	return Snacks.picker.pick({
		source = "recent_created",
		title = "Recently Created",
		items = items,
		format = function(item, picker)
			local ret = { { ("%5s "):format(fmt_age(now - item.created)), "SnacksPickerIdx" } }
			vim.list_extend(ret, require("snacks.picker.format").file(item, picker))
			return ret
		end,
		-- default sort tie-breaks equal scores by text length, which would
		-- scramble the creation order; tie-break by item order instead
		sort = { fields = { "score:desc", "idx" } },
	})
end

return M
