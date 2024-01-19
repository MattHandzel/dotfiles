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
            ["<C-n>"] = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Insert }),
            ["<C-p>"] = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Insert }),
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
      "folke/zen-mode.nvim",
      "ThePrimeagen/harpoon",

      "tpope/vim-fugitive",
      "lewis6991/gitsigns.nvim",

      "navarasu/onedark.nvim", -- Theme inspired by Atom
      "nvim-lualine/lualine.nvim", -- Fancier statusline
      "lukas-reineke/indent-blankline.nvim", -- Add indentation guides even on blank lines "mg979/vim-visual-multi",
    },
    { "catppuccin/nvim", as = "catppuccin" },
    {
      "folke/twilight.nvim",
      opts = {
        dimming = {
          alpha = 0.25, -- amount of dimming
          -- we try to get the foreground from the highlight groups or fallback color
          color = { "Normal", "#ffffff" },
          term_bg = "#000000", -- if guibg=NONE, this will be used to calculate text color
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
      ---@param opts cmp.ConfigSchema
      opts = function(_, opts)
        table.insert(opts.sources, 1, {
          name = "copilot",
          group_index = 1,
          priority = 100,
        })
      end,
    },
    {
      "epwalsh/obsidian.nvim",
      version = "*", -- recommended, use latest release instead of latest commit
      lazy = true,
      ft = "markdown",
      -- Replace the above line with this if you only want to load obsidian.nvim for markdown files in your vault:
      -- event = {
      --   -- If you want to use the home shortcut '~' here you need to call 'vim.fn.expand'.
      --   -- E.g. "BufReadPre " .. vim.fn.expand "~" .. "/my-vault/**.md"
      --   "BufReadPre path/to/my-vault/**.md",
      --   "BufNewFile path/to/my-vault/**.md",
      -- },
      dependencies = {
        -- Required.
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
        "TmuxNavigateLeft",
        "TmuxNavigateDown",
        "TmuxNavigateUp",
        "TmuxNavigateRight",
        "TmuxNavigatePrevious",
      },
      keys = {
        { "<c-h>", "<cmd><C-U>TmuxNavigateLeft<cr>" },
        { "<c-j>", "<cmd><C-U>TmuxNavigateDown<cr>" },
        { "<c-k>", "<cmd><C-U>TmuxNavigateUp<cr>" },
        { "<c-l>", "<cmd><C-U>TmuxNavigateRight<cr>" },
        { "<c-\\>", "<cmd><C-U>TmuxNavigatePrevious<cr>" },
      },
    },
    { import = "plugins" },
  },
  defaults = {
    -- By default, only LazyVim plugins will be lazy-loaded. Your custom plugins will load during startup.
    -- If you know what you're doing, you can set this to `true` to have all your custom plugins lazy-loaded by default.
    lazy = false,
    -- It's recommended to leave version=false for now, since a lot the plugin that support versioning,
    -- have outdated releases, which may break your Neovim install.
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
        -- "netrwPlugin",
        "tarPlugin",
        "tohtml",
        -- "tutor",
        "zipPlugin",
      },
    },
  },
})
