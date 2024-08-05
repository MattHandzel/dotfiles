self: super: {
  command-not-found = super.command-not-found.overrideAttrs (oldAttrs: rec {
    zshInteractiveShellInit = ''
      # This function is called whenever a command is not found.
      command_not_found_handler() {
        local p='${oldAttrs.commandNotFound}/bin/command-not-found'
        if [ -x "$p" ] && [ -f '/var/lib/command-not-found/dbPath' ]; then
          # Run the helper program.
          "$p" "$@"

          # Retry the command if we just installed it.
          if [ $? = 126 ]; then
            "$@"
          else
            return 127
          fi
        else
          # Indicate that there was an error so ZSH falls back to its default handler
          echo "$1: command not found" >&2
          return 127
        fi
      }
    '';
  });
}
