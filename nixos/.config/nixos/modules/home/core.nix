# Settings every profile gets: shell, editor, terminal, prompt, theme.
#
# Imported by ./default.nix (the personal hosts) and by ./work.nix (the
# Redwood-issued MacBook, which gets these and none of the personal jobs).
# Anything that reads the vault, a secret or a personal account belongs in
# ./default.nix, not here.
{inputs, ...}: {
  imports = [
    ./work-flag.nix # the `my.work` switch
    ./theme.nix # palette/font tokens shared across modules
    ./platform.nix # clip-copy / clip-paste / notify / open-it / pick / type-text
    ./bat.nix # better cat command
    ./btop.nix # resouces monitor
    ./git.nix # version control
    ./gtk.nix # fonts on both; the gtk.* theme block is Linux-gated inside
    ./kitty.nix # terminal
    ./nvim.nix # neovim editor
    ./starship.nix # shell prompt
    ./tmux.nix # terminal multiplexer
    ./zsh.nix # shell
    inputs.catppuccin.homeModules.catppuccin
  ];

  catppuccin = {
    flavor = "mocha";
    enable = true;
    # Catppuccin's VSCode module pulls/builds a theme extension; keep it off so
    # rebuilds don't depend on npm registry availability.
    vscode.profiles.default.enable = false;
    # nvim.enable = false;
  };
  catppuccin.delta.enable = false;

  programs.atuin = {
    enable = true;
    settings = {
      accept_past_line_end = true;
      auto_sync = true;
      sync_frequency = "5m";
      sync_address = "https://api.atuin.sh";
      search_mode = "fuzzy";
      keymap_mode = "vim-normal";
      enter_accept = true;
    };
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      # todo: write
    };
  };

  home.sessionVariables = {
    TERMINAL = "kitty";
    EDITOR = "nvim";
    # GDK_BACKEND = "x11"; # Forces XWayland for GTK apps like Foliate
  };
}
