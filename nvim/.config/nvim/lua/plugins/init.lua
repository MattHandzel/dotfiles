return {
	{
		"stevearc/conform.nvim",
		config = function()
			require("configs.conform")
		end,
		lazy = false,
	},

	{
		"ActivityWatch/aw-watcher-vim",
		event = "VeryLazy",
		config = function()
			vim.cmd("AWStart")
			-- require("aw-watcher-vim").start()
		end,
	},
	-- {
	-- 	"vhyrro/luarocks.nvim",
	-- 	priority = 1001, -- this plugin needs to run before anything else
	-- 	opts = {
	-- 		rocks = { "magick" },
	-- 	},
	-- },
	{
		"3rd/image.nvim",
		event = "VeryLazy",
		config = function()
			require("image").setup({
				backend = "kitty",
				processor = "magick_rock", -- or "magick_cli"
				integrations = {
					markdown = {
						enabled = true,
						clear_in_insert_mode = false,
						download_remote_images = true,
						only_render_image_at_cursor = false,
						filetypes = { "markdown", "vimwiki" },
					},
					neorg = {
						enabled = true,
						filetypes = { "norg" },
					},
					typst = {
						enabled = true,
						filetypes = { "typst" },
					},
					html = {
						enabled = false,
					},
					css = {
						enabled = false,
					},
				},
				max_width = nil,
				max_height = nil,
				max_width_window_percentage = nil,
				max_height_window_percentage = 50,
				window_overlap_clear_enabled = false, -- toggles images when windows are overlapped
				window_overlap_clear_ft_ignore = { "cmp_menu", "cmp_docs", "" },
				editor_only_render_when_focused = false, -- auto show/hide images when the editor gains/looses focus
				tmux_show_only_in_active_window = false, -- auto show/hide images in the correct Tmux window (needs visual-activity off)
				hijack_file_patterns = { "*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp", "*.avif" }, -- render image files as images when opened
			})
		end,
	},
	{
		"nvim-treesitter/nvim-treesitter",
		config = function()
			require("nvim-treesitter.configs").setup({
				ensure_installed = { "norg" },
				highlight = { enable = true },
			})
		end,
	},
	-- config = function()
	-- 	require("image").setup({
	-- 		backend = "kitty",
	-- 		processor = "magick_rock", -- or "magick_cli"
	-- 		integrations = {
	-- 			markdown = {
	-- 				enabled = true,
	-- 				clear_in_insert_mode = false,
	-- 				download_remote_images = true,
	-- 				only_render_image_at_cursor = false,
	-- 				filetypes = { "markdown", "vimwiki" }, -- markdown extensions (ie. quarto) can go here
	-- 			},
	-- 			neorg = {
	-- 				enabled = true,
	-- 				filetypes = { "norg" },
	-- 			},
	-- 			typst = {
	-- 				enabled = true,
	-- 				filetypes = { "typst" },
	-- 			},
	-- 			html = {
	-- 				enabled = false,
	-- 			},
	-- 			css = {
	-- 				enabled = false,
	-- 			},
	-- 		},
	-- 		max_width = nil,
	-- 		max_height = nil,
	-- 		max_width_window_percentage = nil,
	-- 		max_height_window_percentage = 50,
	-- 		window_overlap_clear_enabled = false, -- toggles images when windows are overlapped
	-- 		window_overlap_clear_ft_ignore = { "cmp_menu", "cmp_docs", "" },
	-- 		editor_only_render_when_focused = false, -- auto show/hide images when the editor gains/looses focus
	-- 		tmux_show_only_in_active_window = false, -- auto show/hide images in the correct Tmux window (needs visual-activity off)
	-- 		hijack_file_patterns = { "*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp", "*.avif" }, -- render image files as images when opened
	-- 	})
	-- end,
	-- },

	{
		"iamcco/markdown-preview.nvim",
		cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
		build = "cd app && yarn install",
		lazy = false,
		init = function()
			vim.g.mkdp_filetypes = { "markdown" }
		end,
		config = function()
			-- require("markdown-preview").setup({
			-- 	open_browser = {
			-- 		app = "brave",
			-- 	},
			-- })
			-- require("markdown-preview").setup({
			-- 	open_browser = {
			-- 		app = "brave",
			-- 	},
			-- })
		end,
		ft = { "markdown" },
	},

	{
		"MeanderingProgrammer/render-markdown.nvim",
		opts = {},
		config = function()
			require("render-markdown").setup({
				heading = {
					-- Turn on / off heading icon & background rendering
					enabled = true,
					-- Turn on / off any sign column related rendering
					sign = true,
					-- Determines how icons fill the available space:
					--  right:   '#'s are concealed and icon is appended to right side
					--  inline:  '#'s are concealed and icon is inlined on left side
					--  overlay: icon is left padded with spaces and inserted on left hiding any additional '#'
					position = "inline",
					-- Replaces '#+' of 'atx_h._marker'
					-- The number of '#' in the heading determines the 'level'
					-- The 'level' is used to index into the list using a cycle
					icons = { "󰲡 ", "󰲣 ", "󰲥 ", "󰲧 ", "󰲩 ", "󰲫 " },
					-- Added to the sign column if enabled
					-- The 'level' is used to index into the list using a cycle
					signs = { "󰫎 " },
					-- Width of the heading background:
					--  block: width of the heading text
					--  full:  full width of the window
					-- Can also be a list of the above values in which case the 'level' is used
					-- to index into the list using a clamp
					width = "block",
					-- Amount of margin to add to the left of headings
					-- If a floating point value < 1 is provided it is treated as a percentage of the available window space
					-- Margin available space is computed after accounting for padding
					-- Can also be a list of numbers in which case the 'level' is used to index into the list using a clamp
					left_margin = 0.00,
					-- Amount of padding to add to the left of headings
					-- If a floating point value < 1 is provided it is treated as a percentage of the available window space
					-- Can also be a list of numbers in which case the 'level' is used to index into the list using a clamp
					left_pad = 0,
					-- Amount of padding to add to the right of headings when width is 'block'
					-- If a floating point value < 1 is provided it is treated as a percentage of the available window space
					-- Can also be a list of numbers in which case the 'level' is used to index into the list using a clamp
					right_pad = 0,
					-- Minimum width to use for headings when width is 'block'
					-- Can also be a list of integers in which case the 'level' is used to index into the list using a clamp
					min_width = 0,
					-- Determines if a border is added above and below headings
					-- Can also be a list of booleans in which case the 'level' is used to index into the list using a clamp
					border = false,
					-- Always use virtual lines for heading borders instead of attempting to use empty lines
					border_virtual = true,
					-- Highlight the start of the border using the foreground highlight
					border_prefix = true,
					-- Used above heading for border
					above = "▄",
					-- Used below heading for border
					below = "▀",
					-- The 'level' is used to index into the list using a clamp
					-- Highlight for the heading icon and extends through the entire line
					backgrounds = {
						"RenderMarkdownH1Bg",
						"RenderMarkdownH2Bg",
						"RenderMarkdownH3Bg",
						"RenderMarkdownH4Bg",
						"RenderMarkdownH5Bg",
						"RenderMarkdownH6Bg",
					},
					-- The 'level' is used to index into the list using a clamp
					-- Highlight for the heading and sign icons
					foregrounds = {
						"RenderMarkdownH1",
						"RenderMarkdownH2",
						"RenderMarkdownH3",
						"RenderMarkdownH4",
						"RenderMarkdownH5",
						"RenderMarkdownH6",
					},
				},
				checkbox = {
					enabled = true,
					position = "inline",
					unchecked = {
						icon = "󰄱 ",
						highlight = "rendermarkdownunchecked",
						scope_highlight = nil,
					},
					checked = {
						icon = "󰱒 ",
						highlight = "rendermarkdownchecked",
						scope_highlight = nil,
					},
					custom = {
						important = {
							raw = "[!]",
							rendered = " ",
							highlight = "DiagnosticError",
							scope_highlight = nil,
						},
						pending = {
							raw = "[>]",
							rendered = "󰥔 ",
							highlight = "rendermarkdowntodo",
							scope_highlight = nil,
						},
					},
				},
				-- Options go here
			})
		end,
		event = "VeryLazy",
		-- dependencies = { "nvim-treesitter/nvim-treesitter", "echasnovski/mini.nvim" }, -- if you use the mini.nvim suite
		dependencies = { "nvim-treesitter/nvim-treesitter", "echasnovski/mini.icons" }, -- if you use standalone mini plugins
		-- dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" }, -- if you prefer nvim-web-devicons
	},

	{
		"chrisgrieser/cmp_yanky",
		opts = {
			name = "cmp_yanky",
			option = {
				-- only suggest items which match the current filetype
				onlyCurrentFiletype = false,
				-- only suggest items with a minimum length
				minLength = 3,
			},
		},
	},
	{ "dccsillag/magma-nvim", event = "VeryLazy" },
	{
		"lervag/vimtex",
		init = function() end,
		event = "VeryLazy",
	},
	{
		"rareitems/anki.nvim",
		-- lazy -- don't lazy it, it tries to be as lazy possible and it needs to add a filetype association
		event = "VeryLazy",
		opts = {
			{
				-- this function will add support for associating '.anki' extension with both 'anki' and 'tex' filetype.
				tex_support = true,
				models = {
					-- Here you specify which notetype should be associated with which deck
					NoteType = "PathToDeck",
					["Basic"] = "Deck",
					["Super Basic"] = "Deck::ChildDeck",
				},
			},
		},
	},

	{

		"epwalsh/obsidian.nvim",
		event = "VeryLazy",
		-- config = function()
		-- 	require("obsidian").setup({
		-- 		-- your configuration comes here
		-- 	})
		-- end,

		ft = { "markdown" },
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-telescope/telescope.nvim",
			"nvim-treesitter/nvim-treesitter",
			"hrsh7th/nvim-cmp",
		},
		opts = {
			ui = {
				enable = false, -- set to false to disable all additional syntax features
				checkboxes = {
					-- NOTE: the 'char' value has to be a single character, and the highlight groups are defined below.
					[" "] = { char = "󰄱", hl_group = "ObsidianTodo" },
					["x"] = { char = "", hl_group = "ObsidianDone" },
					[">"] = { char = "", hl_group = "ObsidianRightArrow" },
					["!"] = { char = "", hl_group = "ObsidianImportant" },
					-- Replace the above with this if you don't have a patched font:
					-- [" "] = { char = "☐", hl_group = "ObsidianTodo" },
					-- ["x"] = { char = "✔", hl_group = "ObsidianDone" },

					-- You can also add more custom ones...
				},
			},
			workspaces = {
				{
					name = "main",
					path = "~/Obsidian/Main",
				},
			},
			daily_notes = {
				-- Optional, if you keep daily notes in a separate directory.
				folder = "notes/dailies",
				-- Optional, if you want to change the date format for the ID of daily notes.
				date_format = "%Y-%m-%d",
				-- Optional, if you want to change the date format of the default alias of daily notes.
				alias_format = "%B %-d, %Y",
				-- Optional, default tags to add to each new daily note created.
				default_tags = { "daily-notes" },
				-- Optional, if you want to automatically insert a template from your template directory like 'daily.md'
				template = "daily note",
			},
			templates = {
				folder = "templates",
				date_format = "%Y-%m-%d",
				time_format = "%H:%M",
				-- A map for custom variables, the key should be the variable and the value a function
				substitutions = {},
			},

			-- Optional, by default when you use `:ObsidianFollowLink` on a link to an external
			-- URL it will be ignored but you can customize this behavior here.
			---@param url string
			follow_url_func = function(url)
				-- Open the URL in the default web browser.
				vim.fn.jobstart({ "xdg-open", url }) -- linux
				-- vim.cmd(':silent exec "!start ' .. url .. '"') -- Windows
				-- vim.ui.open(url) -- need Neovim 0.10.0+
			end,

			-- Optional, by default when you use `:ObsidianFollowLink` on a link to an image
			-- file it will be ignored but you can customize this behavior here.
			---@param img string
			follow_img_func = function(img)
				vim.fn.jobstart({ "xdg-open", img }) -- linux
				-- vim.cmd(':silent exec "!start ' .. url .. '"') -- Windows
			end,

			--     -- your configuration comes here
			completion = {
				-- Set to false to disable completion.
				nvim_cmp = true,
				-- Trigger completion at 2 chars.
				min_chars = 2,
			},
			note_frontmatter_func = function(note)
				-- List of articles to exclude from capitalization
				local articles = {
					["a"] = true,
					["an"] = true,
					["the"] = true,
					["and"] = true,
					["or"] = true,
					["but"] = true,
					["of"] = true,
					["in"] = true,
					["on"] = true,
					["with"] = true,
					["to"] = true,
					["for"] = true,
				}

				-- Helper function to capitalize words, excluding articles
				local function capitalize_title_simple(title)
					local words = {}
					local first_word = true

					for _, word in ipairs(vim.split(title, " ", { plain = true })) do
						word = word:lower()
						if first_word or not articles[word] then
							table.insert(words, word:sub(1, 1):upper() .. word:sub(2)) -- Capitalize first letter
						else
							table.insert(words, word) -- Keep articles lowercase
						end
						first_word = false
					end

					return table.concat(words, " ")
				end

				-- Add the title of the note as an alias
				if note.title == nil and note.id then
					note.title = capitalize_title_simple(note.id:gsub("%-", " "))
					print("We are setting the title to", note.id)
				end

				if note.title then
					note:add_alias(note.title)
					local formatted_name = note.title:lower():gsub("%s", "-")
					if formatted_name ~= note.title:lower() then
						note:add_alias(formatted_name)
					end
					-- formatted_name = capitalize_title_simple(note.title:gsub("%-", " "))
					-- if formatted_name ~= note.title then
					-- 	note:add_alias(formatted_name)
					-- end
				end

				-- Add current date to metadata
				local current_date = os.date("%Y-%m-%d") -- Format: YYYY-MM-DD
				if note.metadata == nil then
					note.metadata = {}
				end

				if note.metadata.created_date == nil then
					note.metadata.created_date = current_date
				end
				note.metadata.last_edited_date = current_date

				local out = { id = note.id, aliases = note.aliases, tags = note.tags }

				-- Ensure manually added fields in the frontmatter are kept
				if note.metadata ~= nil and not vim.tbl_isempty(note.metadata) then
					for k, v in pairs(note.metadata) do
						out[k] = v
					end
				end

				return out
			end,
		},
	},
	{
		default_keymappings_enabled = false,
		"johmsalas/text-case.nvim",
		dependencies = { "nvim-telescope/telescope.nvim" },
		config = function()
			require("textcase").setup({})
			require("telescope").load_extension("textcase")
		end,
		prefix = "ga",
		keys = {
			"ga", -- Default invocation prefix
			{ "ga?", "<cmd>TextCaseOpenTelescope<CR>", mode = { "n", "x" }, desc = "Telescope" },
		},
		cmd = {
			-- NOTE: The Subs command name can be customized via the option "substitude_command_name"
			"Subs",
			"TextCaseOpenTelescope",
			"TextCaseOpenTelescopeQuickChange",
			"TextCaseOpenTelescopeLSPChange",
			"TextCaseStartReplacingCommand",
		},
		-- If you want to use the interactive feature of the `Subs` command right away, text-case.nvim
		-- has to be loaded on startup. Otherwise, the interactive feature of the `Subs` will only be
		-- available after the first executing of it or after a keymap of text-case.nvim has been used.
		lazy = false,
	},

	{
		"s1n7ax/nvim-window-picker",
		name = "window-picker",
		event = "VeryLazy",
		version = "2.*",
		config = function()
			require("window-picker").setup({
				-- type of hints you want to get
				-- following types are supported
				-- 'statusline-winbar' | 'floating-big-letter' | 'floating-letter'
				-- 'statusline-winbar' draw on 'statusline' if possible, if not 'winbar' will be
				-- 'floating-big-letter' draw big letter on a floating window
				-- 'floating-letter' draw letter on a floating window
				-- used
				hint = "statusline-winbar",

				-- when you go to window selection mode, status bar will show one of
				-- following letters on them so you can use that letter to select the window
				selection_chars = "AOEIHTNSUD",

				-- This section contains picker specific configurations
				picker_config = {
					statusline_winbar_picker = {
						-- You can change the display string in status bar.
						-- It supports '%' printf style. Such as `return char .. ': %f'` to display
						-- buffer file path. See :h 'stl' for details.
						selection_display = function(char, windowid)
							return "%=" .. char .. "%="
						end,

						-- whether you want to use winbar instead of the statusline
						-- "always" means to always use winbar,
						-- "never" means to never use winbar
						-- "smart" means to use winbar if cmdheight=0 and statusline if cmdheight > 0
						use_winbar = "never", -- "always" | "never" | "smart"
					},

					floating_big_letter = {
						-- window picker plugin provides bunch of big letter fonts
						-- fonts will be lazy loaded as they are being requested
						-- additionally, user can pass in a table of fonts in to font
						-- property to use instead

						font = "ansi-shadow", -- ansi-shadow |
					},
				},

				-- whether to show 'Pick window:' prompt
				show_prompt = true,

				-- prompt message to show to get the user input
				prompt_message = "Pick window: ",

				-- if you want to manually filter out the windows, pass in a function that
				-- takes two parameters. You should return window ids that should be
				-- included in the selection
				-- EX:-
				-- function(window_ids, filters)
				--    -- folder the window_ids
				--    -- return only the ones you want to include
				--    return {1000, 1001}
				-- end
				filter_func = nil,

				-- following filters are only applied when you are using the default filter
				-- defined by this plugin. If you pass in a function to "filter_func"
				-- property, you are on your own
				filter_rules = {
					-- when there is only one window available to pick from, use that window
					-- without prompting the user to select
					autoselect_one = true,

					-- whether you want to include the window you are currently on to window
					-- selection or not
					include_current_win = false,

					-- whether to include windows marked as unfocusable
					include_unfocusable_windows = false,

					-- filter using buffer options
					bo = {
						-- if the file type is one of following, the window will be ignored
						filetype = { "NvimTree", "neo-tree", "notify", "snacks_notif" },

						-- if the file type is one of following, the window will be ignored
						buftype = { "terminal" },
					},

					-- filter using window options
					wo = {},

					-- if the file path contains one of following names, the window
					-- will be ignored
					file_path_contains = {},

					-- if the file name contains one of following names, the window will be
					-- ignored
					file_name_contains = {},
				},

				-- You can pass in the highlight name or a table of content to set as
				-- highlight
				highlights = {
					enabled = true,
					statusline = {
						focused = {
							fg = "#ededed",
							bg = "#e35e4f",
							bold = true,
						},
						unfocused = {
							fg = "#ededed",
							bg = "#44cc41",
							bold = true,
						},
					},
					winbar = {
						focused = {
							fg = "#ededed",
							bg = "#e35e4f",
							bold = true,
						},
						unfocused = {
							fg = "#ededed",
							bg = "#44cc41",
							bold = true,
						},
					},
				},
			})
		end,
	},

	-- {
	-- 	"filipdutescu/renamer.nvim",
	-- 	dependencies = { "nvim-lua/plenary.nvim" },
	-- },
	{
		"folke/noice.nvim",
		event = "VeryLazy",

		opts = {
			lsp = {
				override = {
					["vim.lsp.util.convert_input_to_markdown_lines"] = true,
					["vim.lsp.util.stylize_markdown"] = true,
					["cmp.entry.get_documentation"] = true,
				},
				signature = {
					enable = false,
				},
			},
			routes = {
				{
					filter = {
						event = "msg_show",
						kind = "",
						find = "line", -- filter out the filename/path notification on exiting insert mode
					},
					opts = { skip = true },
				},
				{
					filter = {
						event = "msg_show",
						any = {
							{ find = "%d+L, %d+B" },
							{ find = "; after #%d+" },
							{ find = "; before #%d+" },
						},
					},
					view = "mini",
				},
				-- routes = {
				-- 	{
				-- 		filter = {
				-- 			event = "msg_showmode",
				-- 			-- find = "line %d+ of %d+",
				-- 		},
				-- 		opts = { skip = true },
				-- 	},
				-- },
			},
			presets = {
				bottom_search = true,
				command_palette = true,
				long_message_to_split = true,
				inc_rename = true,
			},
		},
    -- stylua: ignore
    keys = {
      { "<S-Enter>",   function() require("noice").redirect(vim.fn.getcmdline()) end,                 mode = "c",                 desc = "Redirect Cmdline" },
      { "<leader>snl", function() require("noice").cmd("last") end,                                   desc = "Noice Last Message" },
      { "<leader>snh", function() require("noice").cmd("history") end,                                desc = "Noice History" },
      { "<leader>sna", function() require("noice").cmd("all") end,                                    desc = "Noice All" },
      { "<leader>snd", function() require("noice").cmd("dismiss") end,                                desc = "Dismiss All" },
      { "<c-f>",       function() if not require("noice.lsp").scroll(4) then return "<c-f>" end end,  silent = true,              expr = true,              desc = "Scroll forward",  mode = { "i", "n", "s" } },
      { "<c-b>",       function() if not require("noice.lsp").scroll(-4) then return "<c-b>" end end, silent = true,              expr = true,              desc = "Scroll backward", mode = { "i", "n", "s" } },
    },
	},

	{
		"stevearc/dressing.nvim",
		opts = {},
	},

	{

		event = "VeryLazy",
		"TobinPalmer/pastify.nvim",
		cmd = { "Pastify", "PastifyAfter" },
		config = function()
			-- require("pastify").setup({
			-- 	opts = {
			-- 		absolute_path = false, -- use absolute or relative path to the working directory
			-- 		apikey = "", -- Api key, required for online saving
			-- 		local_path = "/assets/imgs/", -- The path to put local files in, ex <cwd>/assets/images/<filename>.png
			-- 		save = "local", -- Either 'local' or 'online' or 'local_file'
			-- 		filename = "", -- The file name to save the image as, if empty pastify will ask for a name
			-- 		-- Example function for the file name that I like to use:
			-- 		-- filename = function() return vim.fn.expand("%:t:r") .. '_' .. os.date("%Y-%m-%d_%H-%M-%S") end,
			-- 		-- Example result: 'file_2021-08-01_12-00-00'
			-- 		default_ft = "markdown", -- Default filetype to use
			-- 	},
			-- 	ft = { -- Custom snippets for different filetypes, will replace $IMG$ with the image url
			-- 		html = '<img src="$IMG$" alt="">',
			-- 		markdown = "![]($IMG$)",
			-- 		tex = [[\includegraphics[width=\linewidth]{$IMG$}]],
			-- 		css = 'background-image: url("$IMG$");',
			-- 		js = 'const img = new Image(); img.src = "$IMG$";',
			-- 		xml = '<image src="$IMG$" />',
			-- 		php = '<?php echo "<img src="$IMG$" alt="">"; ?>',
			-- 		python = "# $IMG$",
			-- 		java = "// $IMG$",
			-- 		c = "// $IMG$",
			-- 		cpp = "// $IMG$",
			-- 		swift = "// $IMG$",
			-- 		kotlin = "// $IMG$",
			-- 		go = "// $IMG$",
			-- 		typescript = "// $IMG$",
			-- 		ruby = "# $IMG$",
			-- 		vhdl = "-- $IMG$",
			-- 		verilog = "// $IMG$",
			-- 		systemverilog = "// $IMG$",
			-- 		lua = "-- $IMG$",
			-- 	},
			-- })
		end,
	},

	{
		"gbprod/yanky.nvim",
		opts = function()
			return require("configs.yanky")
		end,
	},
	{
		"debugloop/telescope-undo.nvim",
		dependencies = { -- note how they're inverted to above example
			{
				"nvim-telescope/telescope.nvim",
				dependencies = { "nvim-lua/plenary.nvim" },
			},
		},
		keys = {
			{ -- lazy style key map
				"<leader>fu",
				"<cmd>Telescope undo<cr>",
				desc = "undo history",
			},
		},
		opts = {
			-- don't use `defaults = { }` here, do this in the main telescope spec
			extensions = {
				undo = {
					-- telescope-undo.nvim config, see below
				},
				-- no other extensions here, they can have their own spec too
			},
		},
		config = function(_, opts)
			-- Calling telescope's setup from multiple specs does not hurt, it will happily merge the
			-- configs for us. We won't use data, as everything is in it's own namespace (telescope
			-- defaults, as well as each extension).
			require("telescope").setup(opts)
			require("telescope").load_extension("undo")
		end,
	},
	{
		"folke/flash.nvim",
		event = "VeryLazy",
		opts = {},
		keys = {
			{
				"s",
				mode = { "n", "x", "o" },
				function()
					require("flash").jump()
				end,
				desc = "Flash",
			},
			{
				"S",
				mode = { "n", "x", "o" },
				function()
					require("flash").treesitter()
				end,
				desc = "Flash Treesitter",
			},
			{
				"r",
				mode = "o",
				function()
					require("flash").remote()
				end,
				desc = "Remote Flash",
			},
			{
				"R",
				mode = { "o", "x" },
				function()
					require("flash").treesitter_search()
				end,
				desc = "Treesitter Search",
			},
			{
				"<c-s>",
				mode = { "c" },
				function()
					require("flash").toggle()
				end,
				desc = "Toggle Flash Search",
			},
		},
	},
	{
		"nvim-tree/nvim-tree.lua",
		opts = {
			git = { enable = true },
		},
	},
	-- {
	-- 	"jose-elias-alvarez/null-ls.nvim",
	-- 	opt = function()
	-- 		return require("configs.null-ls")
	-- 	end,
	-- },
	{
		"nvim-neo-tree/neo-tree.nvim",
		branch = "v3.x",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-tree/nvim-web-devicons", -- not strictly required, but recommended
			"MunifTanjim/nui.nvim",
			-- "3rd/image.nvim", -- Optional image support in preview window: See `# Preview Mode` for more information
		},
	},
	{
		"rmagatti/auto-session",
		config = function()
			require("auto-session").setup({
				log_level = "warning",
				enabled = true, -- Enables/disables auto creating, saving and restoring
				root_dir = vim.fn.stdpath("data") .. "/sessions/", -- Root dir where sessions will be stored
				auto_save = true, -- Enables/disables auto saving session on exit
				auto_restore = true, -- Enables/disables auto restoring session on start
				auto_create = true, -- Enables/disables auto creating new session files. Can take a function that should return true/false if a new session file should be created or not
				suppressed_dirs = { "~/", "~/Downloads", "/", "~/notes" }, -- Suppress session restore/create in certain directories
				allowed_dirs = nil, -- Allow session restore/create in certain directories
				auto_restore_last_session = false, -- On startup, loads the last saved session if session for cwd does not exist
				use_git_branch = true, -- Include git branch name in session name
				lazy_support = true, -- Automatically detect if Lazy.nvim is being used and wait until Lazy is done to make sure session is restored correctly. Does nothing if Lazy isn't being used. Can be disabled if a problem is suspected or for debugging
				bypass_save_filetypes = nil, -- List of filetypes to bypass auto save when the only buffer open is one of the file types listed, useful to ignore dashboards
				close_unsupported_windows = true, -- Close windows that aren't backed by normal file before autosaving a session
				args_allow_single_directory = true, -- Follow normal sesion save/load logic if launched with a single directory as the only argument
				args_allow_files_auto_save = false, -- Allow saving a session even when launched with a file argument (or multiple files/dirs). It does not load any existing session first. While you can just set this to true, you probably want to set it to a function that decides when to save a session when launched with file args. See documentation for more detail
				continue_restore_on_error = true, -- Keep loading the session even if there's an error
				show_auto_restore_notif = false, -- Whether to show a notification when auto-restoring
				cwd_change_handling = false, -- Follow cwd changes, saving a session before change and restoring after
				lsp_stop_on_restore = false, -- Should language servers be stopped when restoring a session. Can also be a function that will be called if set. Not called on autorestore from startup
				log_level = "error", -- Sets the log level of the plugin (debug, info, warn, error).

				session_lens = {
					load_on_setup = true, -- Initialize on startup (requires Telescope)
					theme_conf = { -- Pass through for Telescope theme options
						-- layout_config = { -- As one example, can change width/height of picker
						--   width = 0.8,    -- percent of window
						--   height = 0.5,
						-- },
					},
					previewer = false, -- File preview for session picker

					mappings = {
						-- Mode can be a string or a table, e.g. {"i", "n"} for both insert and normal mode
						delete_session = { "i", "<C-D>" },
						alternate_session = { "i", "<C-S>" },
						copy_session = { "i", "<C-Y>" },
					},

					session_control = {
						control_dir = vim.fn.stdpath("data") .. "/auto_session/", -- Auto session control dir, for control files, like alternating between two sessions with session-lens
						control_filename = "session_control.json", -- File name of the session control file
					},
				},
			})
		end,
	},
	{
		"zbirenbaum/copilot.lua",
		cmd = "Copilot",
		build = ":Copilot auth",
		opts = {

			suggestion = { enabled = true },
			debug = false,
			panel = { enabled = false },
			filetypes = {
				markdown = true,
				help = true,
			},
		},
	},

	{
		"zbirenbaum/copilot-cmp",
		dependencies = "copilot.lua",
		opts = {},
		config = function(_, opts)
			local copilot_cmp = require("copilot_cmp")
			copilot_cmp.setup(opts)

			-- attach cmp source whenever copilot attaches
			-- fixes lazy-loading issues with the copilot cmp source
			-- require("lazyvim.util").lsp.on_attach(function(client)
			-- 	if client.name == "copilot" then
			-- 		copilot_cmp._on_insert_enter({})
			-- 	end
			-- end)
		end,
	},
	{
		"nvim-cmp",
		dependencies = {
			{
				"zbirenbaum/copilot-cmp",
				dependencies = "copilot.lua",
				opts = {},
				config = function(_, opts)
					local copilot_cmp = require("copilot_cmp")
					copilot_cmp.setup(opts)

					-- attach cmp source whenever copilot attaches
					-- fixes lazy-loading issues with the copilot cmp source
					-- require("lazyvim.util").lsp.on_attach(function(client)
					-- 	if client.name == "copilot" then
					-- 		copilot_cmp._on_insert_enter({})
					-- 	end
					-- end)
				end,
			},
		},
	},

	{
		"neovim/nvim-lspconfig",
		config = function()
			require("nvchad.configs.lspconfig").defaults()
			require("configs.lspconfig")
		end,
	},

	{
		"williamboman/mason.nvim",
		opts = {
			-- setup = {
			--   rust_analyzer = function()
			--     return true
			--   end,
			-- },
			ensure_installed = {
				"lua-language-server",
				"html-lsp",
				"prettier",
				"stylua",
				"clangd",
				"clang-format",
				"markdown",
				"markdown_inline",
				"rust-analyzer",
				"gopls",
			},
		},
	},

	{
		"rcarriga/nvim-notify",
		config = function()
			require("configs.notify")
		end,
	},
	{
		"folke/snacks.nvim",
		priority = 1000,
		lazy = false,
		---@type snacks.Config
		opts = {
			bigfile = { enabled = true },
			dashboard = { enabled = true },
			explorer = { enabled = true, replace_netrw = true },
			indent = { enabled = true },
			input = { enabled = true },
			notifier = {
				enabled = true,
				timeout = 3000,
			},
			picker = {
				sources = {
					explorer = {
						actions = {
							explorer_del = function(picker) --[[Override]]
								local actions = require("snacks.explorer.actions")
								local Tree = require("snacks.explorer.tree")
								local paths = vim.tbl_map(Snacks.picker.util.path, picker:selected({ fallback = true }))
								if #paths == 0 then
									return
								end
								local what = #paths == 1 and vim.fn.fnamemodify(paths[1], ":p:~:.")
									or #paths .. " files"
								actions.confirm("Put to the trash " .. what .. "?", function()
									local jobs = #paths
									local after_job = function()
										jobs = jobs - 1
										if jobs == 0 then
											picker.list:set_selected()
											actions.update(picker)
										end
									end
									for _, path in ipairs(paths) do
										local err_data = {}
										local cmd = "trash " .. path --[[Actual command to run]]
										local job_id = vim.fn.jobstart(cmd, {
											detach = true,
											on_stderr = function(_, data)
												err_data[#err_data + 1] = table.concat(data, "\n")
											end,
											on_exit = function(_, code)
												pcall(function()
													if code == 0 then
														Snacks.bufdelete({ file = path, force = true })
													else
														local err_msg = vim.trim(table.concat(err_data, ""))
														Snacks.notify.error(
															"Failed to delete `" .. path .. "`:\n- " .. err_msg
														)
													end
													Tree:refresh(vim.fs.dirname(path))
												end)
												after_job()
											end,
										})
										if job_id == 0 then
											after_job()
											Snacks.notify.error("Failed to start the job for: " .. path)
										end
									end
								end)
							end,
						},
					},
				},
			},
			quickfile = { enabled = true },
			scope = { enabled = true },
			scroll = { enabled = false },
			statuscolumn = { enabled = true },
			win = { enabled = true },
			words = { enabled = true },
			styles = {
				notification = {
					-- wo = { wrap = true } -- Wrap notifications
				},
			},
		},
		keys = {
			-- Top Pickers & Explorer
			{
				"<leader><space>",
				function()
					Snacks.picker.smart()
				end,
				desc = "Smart Find Files",
			},
			{
				"<leader>,",
				function()
					Snacks.picker.buffers()
				end,
				desc = "Buffers",
			},
			{
				"<leader>/",
				function()
					Snacks.picker.grep()
				end,
				desc = "Grep",
			},
			{
				"<leader>:",
				function()
					Snacks.picker.command_history()
				end,
				desc = "Command History",
			},
			{
				"<leader>n",
				function()
					Snacks.picker.notifications()
				end,
				desc = "Notification History",
			},
			{
				"<leader>e",
				function()
					Snacks.explorer()
				end,
				desc = "File Explorer",
			},
			-- find
			{
				"<leader>fb",
				function()
					Snacks.picker.buffers()
				end,
				desc = "Buffers",
			},
			{
				"<leader>fc",
				function()
					Snacks.picker.files({ cwd = vim.fn.stdpath("config") })
				end,
				desc = "Find Config File",
			},
			{
				"<leader>ff",
				function()
					Snacks.picker.files()
				end,
				desc = "Find Files",
			},
			{
				"<leader>fg",
				function()
					Snacks.picker.git_files()
				end,
				desc = "Find Git Files",
			},
			{
				"<leader>fp",
				function()
					Snacks.picker.projects()
				end,
				desc = "Projects",
			},
			{
				"<leader>fr",
				function()
					Snacks.picker.recent()
				end,
				desc = "Recent",
			},
			-- git
			{
				"<leader>gb",
				function()
					Snacks.picker.git_branches()
				end,
				desc = "Git Branches",
			},
			{
				"<leader>gl",
				function()
					Snacks.picker.git_log()
				end,
				desc = "Git Log",
			},
			{
				"<leader>gL",
				function()
					Snacks.picker.git_log_line()
				end,
				desc = "Git Log Line",
			},
			{
				"<leader>gs",
				function()
					Snacks.picker.git_status()
				end,
				desc = "Git Status",
			},
			{
				"<leader>gS",
				function()
					Snacks.picker.git_stash()
				end,
				desc = "Git Stash",
			},
			{
				"<leader>gd",
				function()
					Snacks.picker.git_diff()
				end,
				desc = "Git Diff (Hunks)",
			},
			{
				"<leader>gf",
				function()
					Snacks.picker.git_log_file()
				end,
				desc = "Git Log File",
			},
			-- Grep
			{
				"<leader>sb",
				function()
					Snacks.picker.lines()
				end,
				desc = "Buffer Lines",
			},
			{
				"<leader>sB",
				function()
					Snacks.picker.grep_buffers()
				end,
				desc = "Grep Open Buffers",
			},
			{
				"<leader>sg",
				function()
					Snacks.picker.grep()
				end,
				desc = "Grep",
			},
			{
				"<leader>sw",
				function()
					Snacks.picker.grep_word()
				end,
				desc = "Visual selection or word",
				mode = { "n", "x" },
			},
			-- search
			{
				'<leader>s"',
				function()
					Snacks.picker.registers()
				end,
				desc = "Registers",
			},
			{
				"<leader>s/",
				function()
					Snacks.picker.search_history()
				end,
				desc = "Search History",
			},
			{
				"<leader>sa",
				function()
					Snacks.picker.autocmds()
				end,
				desc = "Autocmds",
			},
			{
				"<leader>sb",
				function()
					Snacks.picker.lines()
				end,
				desc = "Buffer Lines",
			},
			{
				"<leader>sc",
				function()
					Snacks.picker.command_history()
				end,
				desc = "Command History",
			},
			{
				"<leader>sC",
				function()
					Snacks.picker.commands()
				end,
				desc = "Commands",
			},
			{
				"<leader>sd",
				function()
					Snacks.picker.diagnostics()
				end,
				desc = "Diagnostics",
			},
			{
				"<leader>sD",
				function()
					Snacks.picker.diagnostics_buffer()
				end,
				desc = "Buffer Diagnostics",
			},
			{
				"<leader>sh",
				function()
					Snacks.picker.help()
				end,
				desc = "Help Pages",
			},
			{
				"<leader>sH",
				function()
					Snacks.picker.highlights()
				end,
				desc = "Highlights",
			},
			{
				"<leader>si",
				function()
					Snacks.picker.icons()
				end,
				desc = "Icons",
			},
			{
				"<leader>sj",
				function()
					Snacks.picker.jumps()
				end,
				desc = "Jumps",
			},
			{
				"<leader>sk",
				function()
					Snacks.picker.keymaps()
				end,
				desc = "Keymaps",
			},
			{
				"<leader>sl",
				function()
					Snacks.picker.loclist()
				end,
				desc = "Location List",
			},
			{
				"<leader>sm",
				function()
					Snacks.picker.marks()
				end,
				desc = "Marks",
			},
			{
				"<leader>sM",
				function()
					Snacks.picker.man()
				end,
				desc = "Man Pages",
			},
			{
				"<leader>sp",
				function()
					Snacks.picker.lazy()
				end,
				desc = "Search for Plugin Spec",
			},
			{
				"<leader>sq",
				function()
					Snacks.picker.qflist()
				end,
				desc = "Quickfix List",
			},
			{
				"<leader>sR",
				function()
					Snacks.picker.resume()
				end,
				desc = "Resume",
			},
			{
				"<leader>su",
				function()
					Snacks.picker.undo()
				end,
				desc = "Undo History",
			},
			{
				"<leader>uC",
				function()
					Snacks.picker.colorschemes()
				end,
				desc = "Colorschemes",
			},
			-- LSP
			{
				"gd",
				function()
					Snacks.picker.lsp_definitions()
				end,
				desc = "Goto Definition",
			},
			{
				"gD",
				function()
					Snacks.picker.lsp_declarations()
				end,
				desc = "Goto Declaration",
			},
			{
				"gr",
				function()
					Snacks.picker.lsp_references()
				end,
				nowait = true,
				desc = "References",
			},
			{
				"gI",
				function()
					Snacks.picker.lsp_implementations()
				end,
				desc = "Goto Implementation",
			},
			{
				"gy",
				function()
					Snacks.picker.lsp_type_definitions()
				end,
				desc = "Goto T[y]pe Definition",
			},
			{
				"<leader>ss",
				function()
					Snacks.picker.lsp_symbols()
				end,
				desc = "LSP Symbols",
			},
			{
				"<leader>sS",
				function()
					Snacks.picker.lsp_workspace_symbols()
				end,
				desc = "LSP Workspace Symbols",
			},
			-- Other
			{
				"<leader>z",
				function()
					Snacks.zen()
				end,
				desc = "Toggle Zen Mode",
			},
			{
				"<leader>Z",
				function()
					Snacks.zen.zoom()
				end,
				desc = "Toggle Zoom",
			},
			{
				"<leader>.",
				function()
					Snacks.scratch()
				end,
				desc = "Toggle Scratch Buffer",
			},
			{
				"<leader>S",
				function()
					Snacks.scratch.select()
				end,
				desc = "Select Scratch Buffer",
			},
			{
				"<leader>n",
				function()
					Snacks.notifier.show_history()
				end,
				desc = "Notification History",
			},
			{
				"<leader>bd",
				function()
					Snacks.bufdelete()
				end,
				desc = "Delete Buffer",
			},
			{
				"<leader>cR",
				function()
					Snacks.rename.rename_file()
				end,
				desc = "Rename File",
			},
			{
				"<leader>gB",
				function()
					Snacks.gitbrowse()
				end,
				desc = "Git Browse",
				mode = { "n", "v" },
			},
			{
				"<leader>gg",
				function()
					Snacks.lazygit()
				end,
				desc = "Lazygit",
			},
			{
				"<leader>un",
				function()
					Snacks.notifier.hide()
				end,
				desc = "Dismiss All Notifications",
			},
			{
				"<c-/>",
				function()
					Snacks.terminal()
				end,
				desc = "Toggle Terminal",
			},

			-- { "<c-_>",      function() Snacks.terminal() end, desc = "which_key_ignore" },
			{
				"]]",
				function()
					Snacks.words.jump(vim.v.count1)
				end,
				desc = "Next Reference",
				mode = { "n", "t" },
			},
			{
				"[[",
				function()
					Snacks.words.jump(-vim.v.count1)
				end,
				desc = "Prev Reference",
				mode = { "n", "t" },
			},
			{
				"<leader>N",
				desc = "Neovim News",
				function()
					Snacks.win({
						file = vim.api.nvim_get_runtime_file("doc/news.txt", false)[1],
						width = 0.6,
						height = 0.6,
						wo = {
							spell = false,
							wrap = false,
							signcolumn = "yes",
							statuscolumn = " ",
							conceallevel = 3,
						},
					})
				end,
			},
		},
		init = function()
			vim.api.nvim_create_autocmd("User", {
				pattern = "VeryLazy",
				callback = function()
					-- Setup some globals for debugging (lazy-loaded)
					_G.dd = function(...)
						Snacks.debug.inspect(...)
					end
					_G.bt = function()
						Snacks.debug.backtrace()
					end
					vim.print = _G.dd -- Override print to use snacks for `:=` command

					-- Create some toggle mappings
					Snacks.toggle.option("spell", { name = "Spelling" }):map("<leader>us")
					Snacks.toggle.option("wrap", { name = "Wrap" }):map("<leader>uw")
					Snacks.toggle.option("relativenumber", { name = "Relative Number" }):map("<leader>uL")
					Snacks.toggle.diagnostics():map("<leader>ud")
					Snacks.toggle.line_number():map("<leader>ul")
					Snacks.toggle
						.option("conceallevel", { off = 0, on = vim.o.conceallevel > 0 and vim.o.conceallevel or 2 })
						:map("<leader>uc")
					Snacks.toggle.treesitter():map("<leader>uT")
					Snacks.toggle
						.option("background", { off = "light", on = "dark", name = "Dark Background" })
						:map("<leader>ub")
					Snacks.toggle.inlay_hints():map("<leader>uh")
					Snacks.toggle.indent():map("<leader>ug")
					Snacks.toggle.dim():map("<leader>uD")
				end,
			})
		end,
	},
	-- {
	--   "folke/snacks.nvim",
	--   priority = 1000,
	--   lazy = false,
	--   ---@type snacks.Config
	--   opts = {
	--     -- your configuration comes here
	--     -- or leave it empty to use the default settings
	--     -- refer to the configuration section below
	--     bigfile = { enabled = true },
	--     dashboard = { enabled = true },
	--     explorer = { enabled = true },
	--     indent = { enabled = true },
	--     input = { enabled = true },
	--     picker = { enabled = true },
	--     notifier = { enabled = true },
	--     quickfile = { enabled = true },
	--     scope = { enabled = true },
	--     scroll = { enabled = false },
	--     statuscolumn = { enabled = true },
	--     words = { enabled = true },
	--   },
	-- },
	{
		"lewis6991/gitsigns.nvim",
		event = "VeryLazy",
		config = function()
			require("gitsigns").setup({
				signs = {
					add = { text = "┃" },
					change = { text = "┃" },
					delete = { text = "_" },
					topdelete = { text = "‾" },
					changedelete = { text = "~" },
					untracked = { text = "┆" },
				},
				signs_staged = {
					add = { text = "┃" },
					change = { text = "┃" },
					delete = { text = "_" },
					topdelete = { text = "‾" },
					changedelete = { text = "~" },
					untracked = { text = "┆" },
				},
				signs_staged_enable = true,
				signcolumn = true, -- Toggle with `:Gitsigns toggle_signs`
				numhl = false, -- Toggle with `:Gitsigns toggle_numhl`
				linehl = false, -- Toggle with `:Gitsigns toggle_linehl`
				word_diff = false, -- Toggle with `:Gitsigns toggle_word_diff`
				watch_gitdir = {
					follow_files = true,
				},
				auto_attach = true,
				attach_to_untracked = false,
				current_line_blame = false, -- Toggle with `:Gitsigns toggle_current_line_blame`
				current_line_blame_opts = {
					virt_text = true,
					virt_text_pos = "eol", -- 'eol' | 'overlay' | 'right_align'
					delay = 1000,
					ignore_whitespace = false,
					virt_text_priority = 100,
					use_focus = true,
				},
				current_line_blame_formatter = "<author>, <author_time:%R> - <summary>",
				sign_priority = 6,
				update_debounce = 100,
				status_formatter = nil, -- Use default
				max_file_length = 40000, -- Disable if file is longer than this (in lines)
				preview_config = {
					-- Options passed to nvim_open_win
					border = "single",
					style = "minimal",
					relative = "cursor",
					row = 0,
					col = 1,
				},
			})
		end,
	},

	{

		"CRAG666/code_runner.nvim",
		config = function()
			require("code_runner").setup({
				filetype_path = vim.fn.expand("~/.config/nvim/code_runner_filetypes.json"),
				project_path = vim.fn.expand("~/.config/nvim/code_runner_projects.json"),
				mode = "toggleterm",
			})
		end,
	},

	{
		event = "VeryLazy",
		"CopilotC-Nvim/CopilotChat.nvim",
		branch = "main",
		dependencies = {
			{ "zbirenbaum/copilot.lua" }, -- or github/copilot.vim
			{ "nvim-lua/plenary.nvim" }, -- for curl, log wrapper
		},
		build = "make tiktoken", -- Only on MacOS or Linux
		opts = {
			debug = true, -- Enable debugging
		},
	},
	{

		"CRAG666/betterTerm.nvim",
		"mateuszwieloch/automkdir.nvim",
		"jghauser/mkdir.nvim",
		"GCBallesteros/jupytext.nvim",

		"theprimeagen/harpoon",
		"lukas-reineke/indent-blankline.nvim", -- add indentation guides even on blank lines "mg979/vim-visual-multi",
		"nvim-lua/plenary.nvim",
		"tpope/vim-fugitive",
		"kazhala/close-buffers.nvim",
		"xiyaowong/link-visitor.nvim",
		"ragnarok22/whereami.nvim",
		"terryma/vim-multiple-cursors",
		"gaborvecsei/usage-tracker.nvim",

		"monaqa/dial.nvim",
		-- neotest
		"nvim-neotest/neotest-python",
		"alfaix/neotest-gtest",
	},

	{
		"yorickpeterse/nvim-pqf",
		event = "VeryLazy",
	},

	{
		"christoomey/vim-tmux-navigator",
		lazy = false,
		cmd = {
			"Tmuxnavigateleft",
			"Tmuxnavigatedown",
			"Tmuxnavigateup",
			"Tmuxnavigateright",
			"Tmuxnavigateprevious",
		},
		keys = {
			{ "<c-h>", "<cmd><c-u>Tmuxnavigateleft<cr>" },
			{ "<c-j>", "<cmd><c-u>Tmuxnavigatedown<cr>" },
			{ "<c-k>", "<cmd><c-u>Tmuxnavigateup<cr>" },
			{ "<c-l>", "<cmd><c-u>Tmuxnavigateright<cr>" },
			{ "<c-\\>", "<cmd><c-u>Tmuxnavigateprevious<cr>" },
		},
	},
	{
		"chomosuke/term-edit.nvim",
		lazy = false, -- or ft = 'toggleterm' if you use toggleterm.nvim
		version = "1.*",
	},
	{
		event = "VeryLazy",
		"pocco81/auto-save.nvim",
		config = function()
			require("auto-save").setup({
				enabled = true, -- start auto-save when the plugin is loaded (i.e. when your package manager loads it)
				execution_message = {
					message = function() -- message to print on save
						return ("AutoSave: saved at " .. vim.fn.strftime("%H:%M:%S"))
					end,
					dim = 0.18, -- dim the color of `message`
					cleaning_interval = 1250, -- (milliseconds) automatically clean MsgArea after displaying `message`. See :h MsgArea
				},
				trigger_events = { "InsertLeave", "TextChanged" }, -- vim events that trigger auto-save. See :h events
				condition = function(buf)
					local fn = vim.fn
					local utils = require("auto-save.utils.data")

					if fn.getbufvar(buf, "&modifiable") == 1 and utils.not_in(fn.getbufvar(buf, "&filetype"), {}) then
						return true -- met condition(s), can save
					end
					return false -- can't save
				end,
				write_all_buffers = false, -- write all buffers when the current one meets `condition`
				debounce_delay = 1000, -- saves the file at most every `debounce_delay` milliseconds
				callbacks = { -- functions to be executed at different intervals
					enabling = nil, -- ran when enabling auto-save
					disabling = nil, -- ran when disabling auto-save
					before_asserting_save = nil, -- ran before checking `condition`
					before_saving = nil, -- ran before doing the actual save
					after_saving = nil, -- ran after doing the actual save
				},
			})
		end,
	},

	{
		"nvim-pack/nvim-spectre",
		build = false,
		cmd = "Spectre",
		opts = { open_cmd = "noswapfile vnew" },
    -- stylua: ignore
    keys = {
      { "<leader>sr", function() require("spectre").open() end, desc = "Replace in files (Spectre)" },
    },
	},
	-- {
	-- 	"nvim-telescope/telescope.nvim",
	-- 	cmd = "Telescope",
	-- 	version = false, -- telescope did only one release, so use HEAD for now
	-- 	dependencies = {
	-- 		{
	-- 			"nvim-telescope/telescope-fzf-native.nvim",
	-- 			build = "make",
	-- 			enabled = vim.fn.executable("make") == 1,
	-- 			config = function()
	-- 				on_load("telescope.nvim", function()
	-- 					require("telescope").load_extension("fzf")
	-- 				end)
	-- 			end,
	-- 		},
	-- 	},
	-- 	keys = {
	-- 		{
	-- 			"<leader>,",
	-- 			"<cmd>Telescope buffers sort_mru=true sort_lastused=true<cr>",
	-- 			desc = "Switch Buffer",
	-- 		},
	-- 		{ "<leader>/", telescope("live_grep"), desc = "Grep (root dir)" },
	-- 		{ "<leader>:", "<cmd>Telescope command_history<cr>", desc = "Command History" },
	-- 		{ "<leader><space>", telescope("files"), desc = "Find Files (root dir)" },
	-- 		-- find
	-- 		{ "<leader>fb", "<cmd>Telescope buffers sort_mru=true sort_lastused=true<cr>", desc = "Buffers" },
	-- 		{ "<leader>fc", telescope.config_files(), desc = "Find Config File" },
	-- 		{ "<leader>ff", telescope("files"), desc = "Find Files (root dir)" },
	-- 		{ "<leader>fF", telescope("files", { cwd = false }), desc = "Find Files (cwd)" },
	-- 		{ "<leader>fg", "<cmd>Telescope git_files<cr>", desc = "Find Files (git-files)" },
	-- 		{ "<leader>fr", "<cmd>Telescope oldfiles<cr>", desc = "Recent" },
	-- 		{ "<leader>fR", telescope("oldfiles", { cwd = vim.loop.cwd() }), desc = "Recent (cwd)" },
	-- 		-- git
	-- 		{ "<leader>gc", "<cmd>Telescope git_commits<CR>", desc = "commits" },
	-- 		{ "<leader>gs", "<cmd>Telescope git_status<CR>", desc = "status" },
	-- 		-- search
	-- 		{ '<leader>s"', "<cmd>Telescope registers<cr>", desc = "Registers" },
	-- 		{ "<leader>sa", "<cmd>Telescope autocommands<cr>", desc = "Auto Commands" },
	-- 		{ "<leader>sb", "<cmd>Telescope current_buffer_fuzzy_find<cr>", desc = "Buffer" },
	-- 		{ "<leader>sc", "<cmd>Telescope command_history<cr>", desc = "Command History" },
	-- 		{ "<leader>sC", "<cmd>Telescope commands<cr>", desc = "Commands" },
	-- 		{ "<leader>sd", "<cmd>Telescope diagnostics bufnr=0<cr>", desc = "Document diagnostics" },
	-- 		{ "<leader>sD", "<cmd>Telescope diagnostics<cr>", desc = "Workspace diagnostics" },
	-- 		{ "<leader>sg", telescope("live_grep"), desc = "Grep (root dir)" },
	-- 		{ "<leader>sG", telescope("live_grep", { cwd = false }), desc = "Grep (cwd)" },
	-- 		{ "<leader>sh", "<cmd>Telescope help_tags<cr>", desc = "Help Pages" },
	-- 		{ "<leader>sH", "<cmd>Telescope highlights<cr>", desc = "Search Highlight Groups" },
	-- 		{ "<leader>sk", "<cmd>Telescope keymaps<cr>", desc = "Key Maps" },
	-- 		{ "<leader>sM", "<cmd>Telescope man_pages<cr>", desc = "Man Pages" },
	-- 		{ "<leader>sm", "<cmd>Telescope marks<cr>", desc = "Jump to Mark" },
	-- 		{ "<leader>so", "<cmd>Telescope vim_options<cr>", desc = "Options" },
	-- 		{ "<leader>sR", "<cmd>Telescope resume<cr>", desc = "Resume" },
	-- 		{ "<leader>sw", telescope("grep_string", { word_match = "-w" }), desc = "Word (root dir)" },
	-- 		{ "<leader>sW", telescope("grep_string", { cwd = false, word_match = "-w" }), desc = "Word (cwd)" },
	-- 		{ "<leader>sw", telescope("grep_string"), mode = "v", desc = "Selection (root dir)" },
	-- 		{ "<leader>sW", telescope("grep_string", { cwd = false }), mode = "v", desc = "Selection (cwd)" },
	-- 		{
	-- 			"<leader>uC",
	-- 			telescope("colorscheme", { enable_preview = true }),
	-- 			desc = "Colorscheme with preview",
	-- 		},
	-- 		{
	-- 			"<leader>ss",
	-- 			function()
	-- 				require("telescope.builtin").lsp_document_symbols({
	-- 					symbols = require("lazyvim.config").get_kind_filter(),
	-- 				})
	-- 			end,
	-- 			desc = "Goto Symbol",
	-- 		},
	-- 		{
	-- 			"<leader>sS",
	-- 			function()
	-- 				require("telescope.builtin").lsp_dynamic_workspace_symbols({
	-- 					symbols = require("lazyvim.config").get_kind_filter(),
	-- 				})
	-- 			end,
	-- 			desc = "Goto Symbol (Workspace)",
	-- 		},
	-- 	},
	-- 	opts = function()
	-- 		local actions = require("telescope.actions")
	--
	-- 		local open_with_trouble = function(...)
	-- 			return require("trouble.providers.telescope").open_with_trouble(...)
	-- 		end
	-- 		local open_selected_with_trouble = function(...)
	-- 			return require("trouble.providers.telescope").open_selected_with_trouble(...)
	-- 		end
	-- 		local find_files_no_ignore = function()
	-- 			local action_state = require("telescope.actions.state")
	-- 			local line = action_state.get_current_line()
	-- 			telescope("find_files", { no_ignore = true, default_text = line })()
	-- 		end
	-- 		local find_files_with_hidden = function()
	-- 			local action_state = require("telescope.actions.state")
	-- 			local line = action_state.get_current_line()
	-- 			telescope("find_files", { hidden = true, default_text = line })()
	-- 		end
	--
	-- 		return {
	-- 			defaults = {
	-- 				prompt_prefix = " ",
	-- 				selection_caret = " ",
	-- 				-- open files in the first window that is an actual file.
	-- 				-- use the current window if no other window is available.
	-- 				get_selection_window = function()
	-- 					local wins = vim.api.nvim_list_wins()
	-- 					table.insert(wins, 1, vim.api.nvim_get_current_win())
	-- 					for _, win in ipairs(wins) do
	-- 						local buf = vim.api.nvim_win_get_buf(win)
	-- 						if vim.bo[buf].buftype == "" then
	-- 							return win
	-- 						end
	-- 					end
	-- 					return 0
	-- 				end,
	-- 				mappings = {
	-- 					i = {
	-- 						["<c-t>"] = open_with_trouble,
	-- 						["<a-t>"] = open_selected_with_trouble,
	-- 						["<a-i>"] = find_files_no_ignore,
	-- 						["<a-h>"] = find_files_with_hidden,
	-- 						["<C-Down>"] = actions.cycle_history_next,
	-- 						["<C-Up>"] = actions.cycle_history_prev,
	-- 						["<C-f>"] = actions.preview_scrolling_down,
	-- 						["<C-b>"] = actions.preview_scrolling_up,
	-- 					},
	-- 					n = {
	-- 						["q"] = actions.close,
	-- 					},
	-- 				},
	-- 			},
	-- 		}
	-- 	end,
	-- },
	{
		"folke/trouble.nvim",
		opts = {}, -- for default options, refer to the configuration section for custom setup.
		cmd = "Trouble",
		keys = {
			{
				"<leader>xx",
				"<cmd>Trouble diagnostics toggle<cr>",
				desc = "Diagnostics (Trouble)",
			},
			{
				"<leader>xX",
				"<cmd>Trouble diagnostics toggle filter.buf=0<cr>",
				desc = "Buffer Diagnostics (Trouble)",
			},
			{
				"<leader>cs",
				"<cmd>Trouble symbols toggle focus=false<cr>",
				desc = "Symbols (Trouble)",
			},
			{
				"<leader>cl",
				"<cmd>Trouble lsp toggle focus=false win.position=right<cr>",
				desc = "LSP Definitions / references / ... (Trouble)",
			},
			{
				"<leader>xL",
				"<cmd>Trouble loclist toggle<cr>",
				desc = "Location List (Trouble)",
			},
			{
				"<leader>xQ",
				"<cmd>Trouble qflist toggle<cr>",
				desc = "Quickfix List (Trouble)",
			},
		},
	},
	{
		"folke/flash.nvim",
		event = "VeryLazy",
		vscode = true,
		opts = {},
    -- stylua: ignore
    keys = {
      { "s",     mode = { "n", "x", "o" }, function() require("flash").jump() end,              desc = "Flash" },
      { "S",     mode = { "n", "o", "x" }, function() require("flash").treesitter() end,        desc = "Flash Treesitter" },
      { "r",     mode = "o",               function() require("flash").remote() end,            desc = "Remote Flash" },
      { "R",     mode = { "o", "x" },      function() require("flash").treesitter_search() end, desc = "Treesitter Search" },
      { "<c-s>", mode = { "c" },           function() require("flash").toggle() end,            desc = "Toggle Flash Search" },
    },
		{
			"nvim-telescope/telescope.nvim",
			optional = true,
			opts = function(_, opts)
				local function flash(prompt_bufnr)
					require("flash").jump({
						pattern = "^",
						label = { after = { 0, 0 } },
						search = {
							mode = "search",
							exclude = {
								function(win)
									return vim.bo[vim.api.nvim_win_get_buf(win)].filetype ~= "TelescopeResults"
								end,
							},
						},
						action = function(match)
							local picker = require("telescope.actions.state").get_current_picker(prompt_bufnr)
							picker:set_selection(match.pos[1] - 1)
						end,
					})
				end
				opts.defaults = vim.tbl_deep_extend("force", opts.defaults or {}, {
					mappings = { n = { s = flash }, i = { ["<c-s>"] = flash } },
				})
			end,
		},
	},
	{
		"RRethy/vim-illuminate",
		event = "VeryLazy",
		opts = {
			delay = 200,
			large_file_cutoff = 2000,
			large_file_overrides = {
				providers = { "lsp" },
			},
		},
		config = function(_, opts)
			require("illuminate").configure(opts)

			local function map(key, dir, buffer)
				vim.keymap.set("n", key, function()
					require("illuminate")["goto_" .. dir .. "_reference"](false)
				end, { desc = dir:sub(1, 1):upper() .. dir:sub(2) .. " Reference", buffer = buffer })
			end

			map("]]", "next")
			map("[[", "prev")

			-- also set it after loading ftplugins, since a lot overwrite [[ and ]]
			vim.api.nvim_create_autocmd("FileType", {
				callback = function()
					local buffer = vim.api.nvim_get_current_buf()
					map("]]", "next", buffer)
					map("[[", "prev", buffer)
				end,
			})
		end,
		keys = {
			{ "]]", desc = "Next Reference" },
			{ "[[", desc = "Prev Reference" },
		},
	},
	{
		"folke/todo-comments.nvim",
		cmd = { "TodoTrouble", "TodoTelescope" },
		event = "VeryLazy",
		config = true,
    -- stylua: ignore
    keys = {
      { "]t",         function() require("todo-comments").jump_next() end, desc = "Next todo comment" },
      { "[t",         function() require("todo-comments").jump_prev() end, desc = "Previous todo comment" },
      { "<leader>xt", "<cmd>TodoTrouble<cr>",                              desc = "Todo (Trouble)" },
      { "<leader>xT", "<cmd>TodoTrouble keywords=TODO,FIX,FIXME<cr>",      desc = "Todo/Fix/Fixme (Trouble)" },
      { "<leader>st", "<cmd>TodoTelescope<cr>",                            desc = "Todo" },
      { "<leader>sT", "<cmd>TodoTelescope keywords=TODO,FIX,FIXME<cr>",    desc = "Todo/Fix/Fixme" },
    },
	},

	-- Plug 'romgrk/todoist.nvim', { 'do': ':TodoistInstall' }
	{
		"romgrk/todoist.nvim",
		run = ":TodoistInstall",
		event = "VeryLazy",
	},
	{ -- required by autolink my plan
		"MunifTanjim/nui.nvim",
		requires = { "nvim-lua/plenary.nvim" },
	},
	{
		"MattHandzel/semantic-search-nvim",

		event = "VeryLazy",

		config = function()
			-- require("semantic-search-nvim").setup({
			-- 	threshold = 0.6,
			-- }) -- custom command
		end,
	},

	{
		"3rd/diagram.nvim",
		event = "VeryLazy",
		dependencies = { "3rd/image.nvim" },
		config = function()
			require("diagram").setup({
				default_engine = "mermaid",
				filetypes = {
					markdown = "mermaid",
					plantuml = "plantuml",
					norg = "mermaid",
				},
			})
		end,
	},
	{
		"Groveer/plantuml.nvim",
		event = "VeryLazy",
		config = function()
			require("plantuml").setup({ renderer = "text" })
		end,
	},

	{ "mfussenegger/nvim-dap", event = "VeryLazy" },
	-- {
	-- 	"olexsmir/gopher.nvim",
	-- 	ft = "go",
	-- 	config = function()
	-- 		require("gopher").setup({
	-- 			commands = {
	-- 				go = "go",
	-- 				gomodifytags = "gomodifytags",
	-- 				gotests = "gotests",
	-- 				impl = "impl",
	-- 				iferr = "iferr",
	-- 				dlv = "dlv",
	-- 			},
	-- 			gotests = {
	-- 				-- gotests doesn't have template named "default" so this plugin uses "default" to set the default template
	-- 				template = "default",
	-- 				-- path to a directory containing custom test code templates
	-- 				template_dir = nil,
	-- 				-- switch table tests from using slice to map (with test name for the key)
	-- 				-- works only with gotests installed from develop branch
	-- 				named = false,
	-- 			},
	-- 			gotag = {
	-- 				transform = "snakecase",
	-- 			},
	-- 		})
	-- 	end,
	-- 	-- branch = "develop", -- if you want develop branch
	-- 	-- keep in mind, it might break everything
	-- 	dependencies = {
	-- 		"nvim-lua/plenary.nvim",
	-- 		"nvim-treesitter/nvim-treesitter",
	-- 		"mfussenegger/nvim-dap", -- (optional) only if you use `gopher.dap`
	-- 	},
	-- 	-- (optional) will update plugin's deps on every update
	-- 	build = function()
	-- 		vim.cmd.GoInstallDeps()
	-- 	end,
	-- 	---@type gopher.Config
	-- 	opts = {},
	-- },
	{ "hat0uma/csvview.nvim", opts = { ... }, event = "VeryLazy" },
	{
		"DAmesberger/sc-im.nvim",
		event = "VeryLazy",
		-- opts = {
		-- 	ft = "scim",
		-- 	include_sc_file = true,
		-- 	update_sc_from_md = true,
		-- 	link_fmt = 1,
		-- 	split = "floating",
		-- 	float_config = {
		-- 		height = 0.9,
		-- 		width = 0.9,
		-- 		style = "minimal",
		-- 		border = "single",
		-- 		hl = "Normal",
		-- 		blend = 0,
		-- 	},
		-- },
	},
	{
		"rmanocha/linear-nvim",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-telescope/telescope.nvim",
			"stevearc/dressing.nvim",
		},
		config = function()
			require("linear-nvim").setup()
		end,
	},
	-- {
	--   'mrcjkb/rustaceanvim',
	--   version = '^5',
	--   event = "VeryLazy",
	--
	-- },

	-- {
	--   'simrat39/rust-tools.nvim',
	--   event="VeryLazy",
	--   config = function()
	--     require('rust-tools').setup({
	--     tools = {
	--       autoSetHints = true,
	--       hover_with_actions = true,
	--       runnables = {
	--         use_telescope = true
	--       },
	--       inlay_hints = {
	--         show_parameter_hints = true,
	--         parameter_hints_prefix = "<-",
	--         other_hints_prefix = "=>",
	--       },
	--     },
	--
	--     })
	--   end
	-- },
	{
		"saecki/crates.nvim",
		ft = { "rust", "toml" },
		config = function()
			require("crates").setup({
				completion = {
					cmp = {
						enabled = true,
					},
				},
			})
			require("cmp").setup.buffer({
				sources = { { name = "crates" } },
			})
		end,
	},
	{
		"nvim-pack/nvim-spectre",
		event = "VeryLazy",
		lazy = false,
		cmd = "Spectre",
		opts = {
			open_cmd = "noswapfile vnew",
		},
	},
	-- {
	-- 	"nvim-orgmode/orgmode",
	-- 	event = "VeryLazy",
	-- 	opts = {},
	-- 	config = function(_, opts)
	-- 		require("orgmode").setup(opts)
	-- 	end,
	-- },

	{
		"nvim-neorg/neorg",
		build = ":Neorg sync-parsers",
		dependencies = { "nvim-lua/plenary.nvim" }, --, "juniorsundar/neorg-extras" },
		-- branch = "main",
		version = "*",
		event = "VeryLazy",
		config = function()
			require("neorg").setup({
				load = {
					["core.defaults"] = {}, -- Loads default behaviour
					["core.concealer"] = {}, -- Adds pretty icons to your documents
					["core.completion"] = { -- Enables completion
						config = {
							engine = "nvim-cmp",
						},
					},
					["core.dirman"] = { -- Manages Neorg workspaces
						config = {
							workspaces = {
								notes = "~/notes",

								gtd = "~/notes/gtd",
							},
						},
					},
					-- ["external.many-mans"] = {
					-- 	config = {
					-- 		metadata_fold = true, -- If want @data property ... @end to fold
					-- 		code_fold = true, -- If want @code ... @end to fold
					-- 	},
					-- },
					-- ["external.roam"] = {
					-- 	config = {
					-- 		fuzzy_finder = "Snacks", -- OR "Fzf" OR "Snacks". Defaults to "Telescope"
					-- 		fuzzy_backlinks = false, -- Set to "true" for backlinks in fuzzy finder instead of buffer
					-- 		roam_base_directory = "", -- Directory in current workspace to store roam nodes
					-- 		node_name_randomiser = false, -- Tokenise node name suffix for more randomisation
					-- 		node_name_snake_case = false, -- snake_case the names if node_name_randomiser = false
					-- 	},
					-- },
					["core.ui"] = { -- Adds pretty UI elements to Neorg
					},
					["core.ui.calendar"] = { -- Calendar view
					},

					-- ["core.gtd.base"] = { config = { workspace = "gtd" } },
					-- ["core.gtd.ui"] = {},
				},
			})
		end,
	},
}
