return {
	defaults = { lazy = true },
	-- install = { colorscheme = { "nvchad" } },

	ui = {
		icons = {
			ft = "",
			lazy = "󰂠 ",
			loaded = "",
			not_loaded = "",
		},
	},

	performance = {
		rtp = {
			disabled_plugins = {
				"2html_plugin",
				"tohtml",
				"getscript",
				"getscriptPlugin",
				"gzip",
				"logipat",
				"netrw",
				"netrwPlugin",
				"netrwSettings",
				"netrwFileHandlers",
				"matchit",
				"tar",
				"tarPlugin",
				"rrhelper",
				"spellfile_plugin",
				"vimball",
				"vimballPlugin",
				-- "zip",
				-- "zipPlugin",
				"tutor",
				-- "rplugin",
				"optwin",
				"compiler",
				"bugreport",
			},
		},
	},

	change_detection = {
		-- Keep detection on: lazy needs it to re-read plugin specs.
		enabled = true,
		-- But silence the toast. It reads "Config Change Detected. Reloading..."
		-- while all it actually does is Plugin.load() — re-parse the plugin
		-- SPEC. It never re-runs options/mappings/autocommands, and never
		-- re-runs config/opts for an already-loaded plugin. Announcing a reload
		-- that did not happen is worse than silence: the edit looks applied, so
		-- restarting nvim seems like the only fix — at the cost of every
		-- embedded terminal and Claude session in that instance.
		-- Use :ReloadConfig (lua/configs/reload.lua) for a real reload.
		notify = false,
	},
}
