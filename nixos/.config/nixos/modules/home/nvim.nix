{ pkgs, ... }:
{
  programs.neovim = {
    enable = true;
    vimAlias = true;
    extraPackages = with pkgs; [

    ripgrep
    python3
    nodejs
    luarocks
    lua
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
    ];


  };

}
