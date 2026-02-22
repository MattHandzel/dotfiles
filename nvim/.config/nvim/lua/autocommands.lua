-- Define a table to map file types to external programs and their flags
-- Define a function to open files with external programs
-- filetypes: list of file extensions
-- programs: list of commands (with optional flags) corresponding to the filetypes
local function open_with_external_program(filetypes, programs, filepath, filetype)
	-- Iterate through the filetypes and find a match
	for i, ft in ipairs(filetypes) do
		if filetype == ft then
			-- Extract the command details
			local command_info = programs[i]
			local pre_flags = command_info.pre_flags or "" -- Flags before the filename
			local post_flags = command_info.post_flags or "" -- Flags after the filename
			local program = command_info.program -- Program to use

			-- Construct the full command
			local cmd = string.format("%s %s '%s' %s", program, pre_flags, filepath, post_flags)
			os.execute(cmd)
			break
		end
	end
end

local perf_group = vim.api.nvim_create_augroup("ConfigPerformance", { clear = true })
local large_file_size = 1024 * 1024
local large_file_lines = 20000

vim.api.nvim_create_autocmd({ "BufReadPre", "FileReadPre" }, {
	group = perf_group,
	callback = function(args)
		local name = vim.api.nvim_buf_get_name(args.buf)
		if name == "" then
			return
		end

		local stat = vim.uv.fs_stat(name)
		if stat and stat.size > large_file_size then
			vim.b[args.buf].large_file_mode = true
			vim.bo[args.buf].swapfile = false
			vim.bo[args.buf].undofile = false
		end
	end,
})

vim.api.nvim_create_autocmd("BufReadPost", {
	group = perf_group,
	callback = function(args)
		if vim.api.nvim_buf_line_count(args.buf) > large_file_lines then
			vim.b[args.buf].large_file_mode = true
		end

		if not vim.b[args.buf].large_file_mode then
			return
		end

		vim.bo[args.buf].syntax = "off"
		vim.api.nvim_set_option_value("foldmethod", "manual", { win = 0 })
		pcall(vim.treesitter.stop, args.buf)
		vim.diagnostic.enable(false, { bufnr = args.buf })
	end,
})

vim.api.nvim_create_user_command("DiagnosticsToggle", function()
	local enabled = vim.diagnostic.is_enabled({ bufnr = 0 })
	vim.diagnostic.enable(not enabled, { bufnr = 0 })
end, { desc = "Toggle diagnostics for current buffer" })

vim.api.nvim_create_user_command("ConfigProfile", function()
	vim.cmd("Lazy profile")
end, { desc = "Open lazy.nvim profile view" })

vim.api.nvim_create_user_command("ConfigDoctor", function()
	vim.cmd("checkhealth")
end, { desc = "Run Neovim health checks" })

-- Setup autocmd to handle opening files with external programs
vim.api.nvim_create_autocmd("BufReadPost", {
	callback = function()
		local buf = vim.api.nvim_get_current_buf()
		local filename = vim.api.nvim_buf_get_name(buf)
		local filetype = vim.fn.fnamemodify(filename, ":e") -- Get file extension

		-- Define the filetypes and corresponding programs with flags
		local filetypes = { "pdf", "wav", "wav", "zip", "jpg", "png", "gif", "jpeg", "xcf" }
		local programs = {
			{ program = "zathura", pre_flags = "", post_flags = " &" }, -- For PDFs
			{ program = "mpv", pre_flags = "", post_flags = " &" }, -- For WAVs
			{ program = "mp3", pre_flags = "", post_flags = " &" }, -- For MP3s
			{ program = "unzip", pre_flags = "", post_flags = " &" }, -- For ZIP files
			{ program = "feh", pre_flags = "", post_flags = " &" },
			{ program = "feh", pre_flags = "", post_flags = " &" },
			{ program = "feh", pre_flags = "", post_flags = " &" },
			{ program = "feh", pre_flags = "", post_flags = " &" },
			{ program = "gimp", pre_flags = "", post_flags = " &" },
		}

		-- Check if the filetype is handled by an external program
		for _, ft in ipairs(filetypes) do
			if filetype == ft then
				-- Delete the buffer before opening with external program
				vim.api.nvim_buf_delete(buf, { force = false })
				open_with_external_program(filetypes, programs, filename, filetype)
				return
			end
		end
	end,
})

--------
-- add yours here!
vim.api.nvim_create_autocmd("BufWritePre", {
	pattern = "*",
	callback = function(args)
		if vim.b[args.buf].large_file_mode then
			return
		end
		if vim.bo[args.buf].buftype ~= "" then
			return
		end

		local ok, conform = pcall(require, "conform")
		if ok then
			pcall(conform.format, { bufnr = args.buf, lsp_fallback = true, quiet = true })
		end
	end,
})
