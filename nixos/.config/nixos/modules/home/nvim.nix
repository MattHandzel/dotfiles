{
  pkgs,
  config,
  ...
}: {
  programs.neovim = {
    enable = true;
    withNodeJs = true;

    vimAlias = true;
    withPython3 = true;
    extraPython3Packages = ps: with ps; [pynvim black unidecode isort pylatexenc ipykernel ipython];

    extraLuaPackages = ps: [ps.magick ps.neorg];

    # python3.withPackages = (ps: with ps; [neovim pynvim]);
    extraPackages = with pkgs; [
      vimPlugins.nvchad
      vimPlugins.nvchad-ui

      # (nvim-treesitter.withPlugins (p: [p.norg p.norg-meta]))

      ripgrep
      python3
      nodejs
      lua5_1
      lua51Packages.luarocks

      clang # treesitter
      gnumake # treesitter
      clang-tools # clangd
      cmake-language-server # cmake

      mypy

      tree-sitter

      # ghost-text.nvim runtime (MAT-1780). The plugin's server is written in
      # TypeScript and is executed with bun, so bun must be on nvim's PATH or
      # :GhostTextStart fails silently. Bridges nvim <-> a browser textarea so
      # the Grammarly extension can check buffer text (no Grammarly LSP exists).
      bun

      # Langugage servers
      harper # harper-ls — markdown/gitcommit grammar (lua/configs/lspconfig.lua expects it)
      marksman
      yaml-language-server
      nixd
      bash-language-server
      nodePackages.typescript-language-server
      nodePackages.prettier
      pyright
      alejandra

      # gofmt
      gofumpt

      # Nvim image in document
      imagemagick
      websocat # beeper.nvim: Beeper Desktop /v1/ws event feed via vim.system
      sqlite # beeper.nvim: read-only queries on ~/.config/BeeperTexts/index.db
      ghostscript # provides `gs`, required by imagemagick to rasterize PDFs (snacks.nvim image preview)

      # Go
      # gopher-nvim

      pkgs.vimPlugins.nvim-dap
      pkgs.vimPlugins.nvim-dap-go
      pkgs.vimPlugins.nvim-dap-python
      pkgs.vimPlugins.nvim-dap-ui

      pkgs.python3Packages.debugpy # debug adapter for python

      pkgs.sc-im
      jupyter
    ];
    extraConfig = ''
      luafile ${config.home.homeDirectory}/dotfiles/nvim/.config/nvim/nvim.lua
    '';
  };
}
