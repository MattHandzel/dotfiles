{pkgs, ...}: let
  # 1. Create a wrapper script.
  # We need this because nvim must run in a terminal,
  # and we need to strip the "nvim://" prefix from the URI.
  nvim-uri-handler = pkgs.writeShellScriptBin "nvim-uri-handler" ''
    #!/binsh

    # The URI is passed as the first argument, e.g., "nvim:///home/matth/..."
    uri="$1"

    # Use sed to strip the "nvim://" part, leaving the full file path.
    file_path=$(echo "$uri" | sed 's|^nvim://||')

    # ❗️ EDIT THIS LINE ❗️
    # You must launch nvim inside your terminal of choice.
    # Replace 'alacritty' with your terminal (e.g., kitty, wezterm).
    exec alacritty -e nvim "$file_path"

    # --- Other common terminal examples ---
    # exec kitty -e nvim "$file_path"
    # exec wezterm start -- nvim "$file_path"
  '';
in {
  # 2. Add the script to your user's path
  home.packages = [nvim-uri-handler];

  # 3. Create the .desktop file that uses the script
  xdg.desktopEntries."nvim-handler" = {
    name = "Neovim URI Handler";
    comment = "Handles nvim:// URIs and opens them in Neovim";

    # We execute our wrapper script, passing the full URI (%u)
    exec = "${nvim-uri-handler}/bin/nvim-uri-handler %u";

    # Our script launches the terminal, so this can be false
    terminal = false;
    type = "Application";

    # 4. This is the magic line that registers the new scheme
    mimeType = ["x-scheme-handler/nvim"];
  };

  # 5. Set this .desktop file as the default handler for the scheme
  xdg.mimeApps.defaultApplications = {
    "x-scheme-handler/nvim" = "nvim-handler.desktop";
  };
}
