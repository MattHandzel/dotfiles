{ pkgs, ... }:
{
  programs.neovim = {
    enable = true;
    vimAlias = true;
    extraPackages = with pkgs; [

    ripgrep
    python3
    nodejs

     
    # Langugage servers
    marksman
    yaml-language-server
    nixd
    bash-language-server



    ];

  };

}
