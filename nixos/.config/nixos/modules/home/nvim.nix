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
      # `nodePackages` was removed from nixpkgs; both are top-level now.
      typescript-language-server
      prettier
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
      " fff.nvim ships a Rust backend (libfff_nvim.dylib). The plugin's own
      " installer would `cargo build --release` or download a GitHub release at
      " runtime -- neither works here (cargo is not on PATH, and a downloaded
      " binary is not declarative). nixpkgs' vimPlugins.fff-nvim is the prebuilt
      " plugin with its `get_binary_dir` patched to the store path of the dylib,
      " so the only thing lua needs is where that store path is. lazy.nvim picks
      " it up as `dir = vim.g.fff_nvim_dir` (lua/plugins/init.lua); it cannot come
      " in via `programs.neovim.plugins` because lazy resets the runtimepath
      " (performance.rtp.reset defaults to true) and would drop the packpath.
      " Must be set BEFORE the luafile below, which is where lazy.setup runs.
      lua vim.g.fff_nvim_dir = "${pkgs.vimPlugins.fff-nvim}"
      luafile ${config.home.homeDirectory}/dotfiles/nvim/.config/nvim/nvim.lua
    '';
  };
}
