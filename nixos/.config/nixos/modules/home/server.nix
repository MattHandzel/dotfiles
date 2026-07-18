{
  inputs,
  username,
  host,
  ...
}: {
  imports = [
    (import ./theme.nix)
    (import ./bat.nix)
    (import ./btop.nix)
    (import ./git.nix)
    (import ./nvim.nix)
    (import ./packages-server.nix)
    (import ./starship.nix)
    (import ./tmux.nix)
    (import ./zsh.nix)
    (import ./services.nix) # Check if these services are GUI-dependent
    (import ./scripts/scripts.nix) # personal scripts
    ./transcribe-captures.nix
    inputs.catppuccin.homeModules.catppuccin
  ];

  catppuccin = {
    flavor = "mocha";
    enable = true;
  };

  # Shell-history sync. The full home config (modules/home/default.nix) enables
  # Atuin on laptop/desktop, but the server uses this trimmed config and was
  # missing the client — so server history never merged with the other hosts.
  # Same settings as default.nix; public api.atuin.sh backend (client-side
  # encrypted) so all three hosts share one history store.
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

  home.sessionVariables = {
    EDITOR = "nvim";
  };
}
