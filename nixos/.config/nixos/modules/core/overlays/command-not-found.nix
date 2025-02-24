self: super: {
  command-not-found = super.command-not-found.overrideAttrs (oldAttrs: rec {
    zshInteractiveShellInit = ''
      command_not_found_handle() {
          local cmd=$1
          local nix_suggestion packages fuck_suggestion

          # First check Nix packages
          if ! command -v nix-locate >/dev/null; then
              echo "Install nix-index for package suggestions: nix-env -iA nixpkgs.nix-index" >&2
              return 127
          fi

          # Update nix-index if older than 7 days
          if [ ! -f ~/.cache/nix-index ] || find ~/.cache/nix-index -mtime +7 | grep -q .; then
              echo "Updating nix-index..." >&2
              nix-index >/dev/null
          fi

          # Get Nix package suggestions
          nix_suggestion=$(nix-locate --minimal --top-level "/bin/$cmd" 2>/dev/null | head -n1)

          if [ -n "$nix_suggestion" ]; then
              echo "Command not found. Install with:"
              echo "nix shell -p $\{nix_suggestion%% *}"
              return 127
          fi

          # Try typo correction with thefuck
          if command -v fuck >/dev/null; then
              fuck_suggestion=$(fuck --yeah 2>/dev/null | tail -n1)
              if [ -n "$fuck_suggestion" ]; then
                  echo "Did you mean: $fuck_suggestion ? [y/N]"
                  read -r answer
                  if [ "$answer" = "y" ]; then
                      eval "$fuck_suggestion"
                      return $?
                  fi
              fi
          else
              echo "Install thefuck for typo correction: nix-env -iA nixpkgs.thefuck" >&2
          fi

          # Fallback to default message
          echo "$cmd: command not found" >&2
          return 127
      }
    '';
  });
}
