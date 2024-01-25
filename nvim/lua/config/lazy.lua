local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  -- bootstrap lazy.nvim
  -- stylua: ignore
  vim.fn.system({ "git", "clone", "--filter=blob:none", "https://github.com/folke/lazy.nvim.git", "--branch=stable", lazypath })
end
vim.opt.rtp:prepend(vim.env.LAZY or lazypath)
vim.g.python3_host_prog = "/usr/bin/python3"
require("lazy").setup({
  spec = {
    -- add LazyVim and import its plugins
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    -- import any extras modules here
    { import = "lazyvim.plugins.extras.lang.typescript" },
    { import = "lazyvim.plugins.extras.lang.json" },
    { "ycm-core/YouCompleteMe" },
    -- { import = "lazyvim.plugins.extras.ui.mini-animate" },
    -- import/override with your plugins
    {
      "hrsh7th/nvim-cmp",
      version = false, -- last release is way too old
      event = "InsertEnter",
      dependencies = {
        "hrsh7th/cmp-nvim-lsp",
        "hrsh7th/cmp-buffer",
        "hrsh7th/cmp-path",
        "saadparwaiz1/cmp_luasnip",
      },
      opts = function()
        vim.api.nvim_set_hl(0, "CmpGhostText", { link = "Comment", default = true })
        local cmp = require("cmp")
        local defaults = require("cmp.config.default")()
        return {
          completion = {
            completeopt = "menu,menuone,noinsert",
          },
          snippet = {
            expand = function(args)
              require("luasnip").lsp_expand(args.body)
            end,
          },
          mapping = cmp.mapping.preset.insert({
            -- ["<C-n>"] = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Insert }),
            -- ["<C-p>"] = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Insert }),
            ["<C-b>"] = cmp.mapping.scroll_docs(-4),
            ["<C-f>"] = cmp.mapping.scroll_docs(4),
            ["<C-Space>"] = cmp.mapping.complete(),
            ["<C-e>"] = cmp.mapping.abort(),
            ["<CR>"] = cmp.mapping.confirm({ select = true }), -- Accept currently selected item. Set `select` to `false` to only confirm explicitly selected items.
            ["<S-CR>"] = cmp.mapping.confirm({
              behavior = cmp.ConfirmBehavior.Replace,
              select = true,
            }), -- Accept currently selected item. Set `select` to `false` to only confirm explicitly selected items.
            ["<C-CR>"] = function(fallback)
              cmp.abort()
              fallback()
            end,
          }),
          sources = cmp.config.sources({
            { name = "nvim_lsp" },
            { name = "luasnip" },
            { name = "path" },
          }, {
            { name = "buffer" },
          }),
          formatting = {
            format = function(_, item)
              local icons = require("lazyvim.config").icons.kinds
              if icons[item.kind] then
                item.kind = icons[item.kind] .. item.kind
              end
              return item
            end,
          },
          experimental = {
            ghost_text = {
              hl_group = "CmpGhostText",
            },
          },
          sorting = defaults.sorting,
        }
      end,
      ---@param opts cmp.ConfigSchema
      config = function(_, opts)
        for _, source in ipairs(opts.sources) do
          source.group_index = source.group_index or 1
        end
        require("cmp").setup(opts)
      end,
    },
    {
      "telescope.nvim",
      dependencies = {
        "nvim-telescope/telescope-fzf-native.nvim",
        build = "make",
        config = function()
          require("telescope").load_extension("fzf")
        end,
      },
    },
    {
      "kylechui/nvim-surround",
      version = "*", -- Use for stability; omit to use `main` branch for the latest features
      event = "VeryLazy",
      config = function()
        require("nvim-surround").setup({
          -- Configuration here, or leave empty to use defaults
        })
      end,
    },
    {
      "nvim-neotest/neotest",
      dependencies = {
        "nvim-lua/plenary.nvim",
        "antoinemadec/FixCursorHold.nvim",
        "nvim-treesitter/nvim-treesitter",
      },
    },
    {
      "m4xshen/hardtime.nvim",
      dependencies = { "MunifTanjim/nui.nvim", "nvim-lua/plenary.nvim" },
      opts = {},
    },
    {
      "gaborvecsei/usage-tracker.nvim",
      "CRAG666/betterTerm.nvim",
      "folke/zen-mode.nvim",
      "nvim-neotest/neotest-python",
      "alfaix/neotest-gtest",
      "mateuszwieloch/automkdir.nvim",
      "jghauser/mkdir.nvim",
      "CRAG666/code_runner.nvim",
      "GCBallesteros/jupytext.nvim",
      "ragnarok22/whereami.nvim",
      "xiyaowong/link-visitor.nvim",
      "kazhala/close-buffers.nvim",
      "theprimeagen/harpoon",
      "lervag/vimtex",
      "tpope/vim-fugitive",
      "lewis6991/gitsigns.nvim",
      "yorickpeterse/nvim-pqf",
      "nvim-lua/plenary.nvim",
      "navarasu/onedark.nvim", -- theme inspired by atom
      "nvim-lualine/lualine.nvim", -- fancier statusline
      "lukas-reineke/indent-blankline.nvim", -- add indentation guides even on blank lines "mg979/vim-visual-multi",
    },
    { "catppuccin/nvim", as = "catppuccin" },
    {
      "folke/twilight.nvim",
      opts = {
        dimming = {
          alpha = 0.25, -- amount of dimming
          -- we try to get the foreground from the highlight groups or fallback color
          color = { "normal", "#ffffff" },
          term_bg = "#000000", -- if guibg=none, this will be used to calculate text color
          inactive = false, -- when true, other windows will be fully dimmed (unless they contain the same buffer)
        },
        context = 10, -- amount of lines we will try to show around the current line
        treesitter = true, -- use treesitter when available for the filetype
        -- treesitter is used to automatically expand the visible text,
        -- but you can further control the types of nodes that should always be fully expanded
        expand = { -- for treesitter, we we always try to expand to the top-most ancestor with these types
          "function",
          "method",
          "table",
          "if_statement",
        },
        exclude = {}, -- exclude these filetypes
      },
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
            require("lazyvim.util").lsp.on_attach(function(client)
              if client.name == "copilot" then
                copilot_cmp._on_insert_enter({})
              end
            end)
          end,
        },
      },
      ---@param opts cmp.configschema
      opts = function(_, opts)
        table.insert(opts.sources, 1, {
          name = "copilot",
          group_index = 1,
          priority = 100,
        })
      end,
    },
    {
      "chomosuke/term-edit.nvim",
      lazy = false, -- or ft = 'toggleterm' if you use toggleterm.nvim
      version = "1.*",
    },
    {
      "epwalsh/obsidian.nvim",
      version = "*", -- recommended, use latest release instead of latest commit
      lazy = true,
      ft = "markdown",
      -- replace the above line with this if you only want to load obsidian.nvim for markdown files in your vault:
      -- event = {
      --   -- if you want to use the home shortcut '~' here you need to call 'vim.fn.expand'.
      --   -- e.g. "bufreadpre " .. vim.fn.expand "~" .. "/my-vault/**.md"
      --   "bufreadpre path/to/my-vault/**.md",
      --   "bufnewfile path/to/my-vault/**.md",
      -- },
      dependencies = {
        -- required.
        "nvim-lua/plenary.nvim",

        -- see below for full list of optional dependencies 👇
      },
      opts = {
        workspaces = {
          {
            name = "personal",
            path = "~/vaults/personal",
          },
          {
            name = "work",
            path = "~/vaults/work",
          },
        },

        -- see below for full list of options 👇
      },
    },
    {
      "christoomey/vim-tmux-navigator",
      lazy = false,
      cmd = {
        "tmuxnavigateleft",
        "tmuxnavigatedown",
        "tmuxnavigateup",
        "tmuxnavigateright",
        "tmuxnavigateprevious",
      },
      keys = {
        { "<c-h>", "<cmd><c-u>tmuxnavigateleft<cr>" },
        { "<c-j>", "<cmd><c-u>tmuxnavigatedown<cr>" },
        { "<c-k>", "<cmd><c-u>tmuxnavigateup<cr>" },
        { "<c-l>", "<cmd><c-u>tmuxnavigateright<cr>" },
        { "<c-\\>", "<cmd><c-u>tmuxnavigateprevious<cr>" },
      },
    },
    { import = "plugins" },
  },
  defaults = {
    -- by default, only lazyvim plugins will be lazy-loaded. your custom plugins will load during startup.
    -- if you know what you're doing, you can set this to `true` to have all your custom plugins lazy-loaded by default.
    lazy = false,
    -- it's recommended to leave version=false for now, since a lot the plugin that support versioning,
    -- have outdated releases, which may break your neovim install.
    version = false, -- always use the latest git commit
    -- version = "*", -- try installing the latest stable version for plugins that support semver
  },
  install = { colorscheme = { "catpuccino", "habamax" } },
  checker = { enabled = true }, -- automatically check for plugin updates
  performance = {
    rtp = {
      -- disable some rtp plugins
      disabled_plugins = {
        "gzip",
        -- "matchit",
        -- "matchparen",
        -- "netrwplugin",
        "tarplugin",
        "tohtml",
        -- "tutor",
        "zipplugin",
      },
    },
  },
})
