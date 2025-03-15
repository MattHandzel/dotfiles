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
		-- require("conform").format({ bufnr = args.buf })
	end,
})
