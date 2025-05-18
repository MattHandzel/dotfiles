{pkgs, ...}: {
  programs.neovim = {
    enable = true;
    withNodeJs = true;

    vimAlias = true;
    withPython3 = true;
    extraPython3Packages = ps: with ps; [pynvim black unidecode isort pylatexenc];
    extraLuaPackages = ps: [ps.magick];

    # python3.withPackages = (ps: with ps; [neovim pynvim]);
    extraPackages = with pkgs; [
      vimPlugins.nvchad
      vimPlugins.nvchad-ui

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

      # Langugage servers
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

      # Go
      # gopher-nvim

      pkgs.vimPlugins.nvim-dap
      pkgs.vimPlugins.nvim-dap-go
      pkgs.vimPlugins.nvim-dap-python
      pkgs.vimPlugins.nvim-dap-ui

      pkgs.sc-im
    ];
    # TODO: Fix this so it doesn't care about the user
    extraConfig = ''
      luafile /home/matth/dotfiles/nvim/.config/nvim/nvim.lua
    '';
  };
}
