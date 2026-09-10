{
  hostname,
  config,
  pkgs,
  host,
  lib,
  ...
}: let
  sharedVariables = import ../../shared_variables.nix;
  transcribe_file_script = pkgs.writeShellScript "transcribe_file.sh" ''
    #!/usr/bin/env bash
    # replace ~ with home directory
    input_file="$${1/#\~/$HOME}"
    curl -sS http://${sharedVariables.serverIpAddress}/v1/audio/transcriptions -F file=@"$input_file"
  '';
  second-brain-archive-script = pkgs.writeShellScript "second_brain_archive.sh" ''
    #!/usr/bin/env bash
    mv $1 ~/notes/archive/"$1"
  '';
in {
  home.packages = with pkgs; [
    direnv
    lsd
    pay-respects
    tldr
  ];

  programs.command-not-found.enable = true;

  home.file.".config/cliphist/config".text = ''
    -max-items 100000
    -preview-width 1024
  '';
  # setup direnvrc so that when we cd into a dir then we load some vars
  home.file.".direnvrc".text = ''
      use_nix() {
        local shell_file="shell.nix"
        if [[ -f "$shell_file" ]]; then
          direnv load <(nix-shell --pure --command "direnv dump")
        else
          log_status "No shell.nix found."
        fi
      }

      # use_python_venv() {
      #   if [ -d ".venv" ]; then
      #     layout python-venv .venv
      #   elif [ -f "Pipfile" ]; then
      #     layout python-pipenv
      #   elif [ -f "requirements.txt" ]; then
      #     layout python
      #   fi
      # }

      # Combine use_nix and use_python_venv
      load_env() {
        use_nix
        use_python_venv
      }

      layout_nix_python() {
        load_env
      }

      load_env

    HISTFILE="$HOME/.zsh_history"
    HISTSIZE=1000000000
    SAVEHIST=1000000000
    setopt EXTENDED_HISTORY
    RUSTC_WRAPPER=sccache cargo install {package}
  '';

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    history = {
      size = 1000000;
    };

    oh-my-zsh = {
      enable = true;
      plugins = ["git" "fzf" "colored-man-pages"];
    };

    initContent = lib.mkMerge [
      (lib.mkAfter ''
        # Vi mode for command-line editing (must load after oh-my-zsh)
        bindkey -v
        export KEYTIMEOUT=1

        # Suggestion autofill: when a command fails with a "you probably meant X"
        # hint, put X on the NEXT prompt line, pre-filled and editable — one Enter
        # runs it. No retyping.
        #
        # WHY THE FILE HANDOFF: zsh forks a SUBSHELL to run
        # command_not_found_handler (verified: ZSH_SUBSHELL=1 inside it), so a
        # `print -z` there pushes onto the child's buffer stack and is discarded on
        # exit — it silently does nothing. Variable assignments are lost the same
        # way. A file survives the fork, so the handler writes the suggestion and a
        # precmd hook in the PARENT shell replays it into the ZLE buffer. ($$ is the
        # parent's pid even inside a zsh subshell, so both agree on the path.)
        typeset -g __suggest_file="''${XDG_RUNTIME_DIR:-/tmp}/zsh-suggest-$$"

        __suggest_replay() {
          if [[ -s $__suggest_file ]]; then
            print -z -- "$(<$__suggest_file)"
            command rm -f -- "$__suggest_file"
          fi
        }
        autoload -Uz add-zsh-hook
        add-zsh-hook precmd __suggest_replay
        __suggest_cleanup() { command rm -f -- "$__suggest_file"; }
        add-zsh-hook zshexit __suggest_cleanup

        # Missing binary -> NixOS suggests `nix-shell -p <pkg>`. Parse the package
        # out of the hint rather than assuming it equals the command: `nvim`
        # resolves to `nix-shell -p neovim`, not `-p nvim`.
        if (( $+commands[command-not-found] )); then
          command_not_found_handler() {
            local out pkg orig
            out="$(command-not-found "$@" 2>&1)"
            print -u2 -r -- "$out"
            if [[ -o interactive ]]; then
              pkg="$(print -r -- "$out" | grep -oE 'nix-shell -p [A-Za-z0-9_.+-]+' | head -n1)"
              pkg="''${pkg##* }"
              if [[ -n $pkg ]]; then
                orig="''${(j: :)''${(q)@}}"   # original argv, safely requoted
                print -r -- "nix-shell -p $pkg --run ''${(q)orig}" > "$__suggest_file"
              fi
            fi
            return 127
          }
        fi

        # Mirror vi-mode yanks into the Wayland system clipboard.
        if (( $+commands[wl-copy] )); then
          function _yank-to-clipboard() {
            printf '%s' "$CUTBUFFER" | wl-copy 2>/dev/null &!
          }
          function vi-yank-clip()            { zle .vi-yank;            _yank-to-clipboard; }
          function vi-yank-eol-clip()        { zle .vi-yank-eol;        _yank-to-clipboard; }
          function vi-yank-whole-line-clip() { zle .vi-yank-whole-line; _yank-to-clipboard; }
          function vi-delete-clip()          { zle .vi-delete;          _yank-to-clipboard; }
          function vi-change-clip()          { zle .vi-change;          _yank-to-clipboard; }
          function vi-change-eol-clip()      { zle .vi-change-eol;      _yank-to-clipboard; }
          zle -N vi-yank vi-yank-clip
          zle -N vi-yank-eol vi-yank-eol-clip
          zle -N vi-yank-whole-line vi-yank-whole-line-clip
          zle -N vi-delete vi-delete-clip
          zle -N vi-change vi-change-clip
          zle -N vi-change-eol vi-change-eol-clip
        fi

        # zoxide-backed `cd`, but ONLY in real interactive use — never when the
        # shell is spawned by Claude Code / an AI agent. Those shells need the
        # real `cd` builtin; aliasing it to `z` makes `cd /not/yet/created &&
        # mkdir foo` jump to another frecent dir (and emit zoxide's config
        # warning). CLAUDECODE/AI_AGENT are exported by the agent and inherited
        # by its shell-snapshot generator, so the alias never leaks into them.
        if [[ -z "$CLAUDECODE" && -z "$AI_AGENT" ]]; then
          alias cd='z'
        fi
      '')
      (lib.mkBefore ''
        DISABLE_MAGIC_FUNCTIONS=true
        export "MICRO_TRUECOLOR=1"
        # Set window title to the current directory
        precmd() {
          printf "\033]0;%s\007" "$(basename "$PWD")"
        }

        function note() {
          take-note "$*"
        }
        function notec() {
          take-note -c "$*"
        }
        function ntfy() {
          local title="" priority="default" message=""
          while [[ $# -gt 0 ]]; do
            case "$1" in
              -t|--title) title="$2"; shift 2 ;;
              -p|--priority) priority="$2"; shift 2 ;;
              *) message="$*"; shift $# ;;
            esac
          done
          if [[ -z "$message" ]]; then
            echo "Usage: ntfy <message>"
            echo "       ntfy -t <title> <message>"
            echo "       ntfy -t <title> -p <priority> <message>"
            return 1
          fi
          local cmd=(curl -s -H "Priority: $priority" -d "$message" "http://${sharedVariables.serverIpAddress}:8124/claude")
          [[ -n "$title" ]] && cmd+=(-H "Title: $title")
          "''${cmd[@]}" >/dev/null && echo "Sent: $message" || echo "ERROR: failed to send" >&2
        }
        # eval $(pay-respects --alias) # gets fuck command running

        # export TODOIST_API_KEY="$(cat /run/secrets/todoist_api_key)"

        # __conda_setup="$('/home/matth/.conda/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
        # if [ $? -eq 0 ]; then
        #   eval "$__conda_setup"
        # else
        #   if [ -f "/home/matth/.conda/etc/profile.d/conda.sh" ]; then
        #     . "/home/matth/.conda/etc/profile.d/conda.sh"
        #   else
        #     export PATH="/home/matth/.conda/bin:$PATH"
        #   fi
        # fi
        # unset __conda_setup

        function y() {
          local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
          yazi "$@" --cwd-file="$tmp"
          if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
            builtin cd -- "$cwd"
          fi
          rm -f -- "$tmp"
        }

        export PATH="$HOME/.npm-packages/bin:$PATH"
        video-to-trasncript() { ffmpeg -i $1 -vn $(echo $1 | sed 's/\.mp4$/\.mp3/') } # useful function to convert video to audio
      '')
    ];

    shellAliases = {
      record = "wf-recorder --audio=alsa_output.pci-0000_08_00.6.analog-stereo.monitor -f $HOME/Videos/$(date +'%Y%m%d%H%M%S_1.mp4')";

      # Utils
      c = "clear";
      # NOTE: `cd` is intentionally NOT aliased to `z` here. A static alias is
      # captured by every spawned shell — including Claude Code / AI-agent
      # shells — where aliasing `cd` to zoxide is a footgun: `cd /not/yet/created
      # && mkdir foo` makes `z` jump to some other frecent dir and create `foo`
      # in the wrong place, and it prints zoxide's "configuration issue" warning.
      # Defined instead as an interactive-only, non-agent alias in initContent.
      tt = "gtrash put";
      cat = "bat";
      code = "codium";
      py = "python";
      icat = "kitten icat";
      dsize = "du -hs";
      findw = "grep -rl";
      pdf = "tdf";
      open = "xdg-open";
      ls = "eza";
      lst = "eza --tree --level=";

      ps = "procs";
      glo = "tig";
      df = "duf";
      ping = "gping";

      rm = "trash";

      n = "nvim";

      word-count = "wl-paste | wc";
      paste-image = "wl-paste -t image/png >";

      # Nixos
      ns = "nix-shell --run zsh";
      nd = "nix develop";
      nix-shell = "nix-shell --run zsh";

      # notetaker = "kitty sh -c \"cd ~/notes ; neovim .\" --title notetaker --name notetaker --start-as=fullscreen";

      # `git add .` is added because if there is a file not staged then nixos-rebuild won't look for it
      # The only switch that survives a reboot: it is what writes the Home
      # Manager generation into the system generation, which is what
      # home-manager-${user}.service re-activates at every boot. Clearing the
      # stamp is therefore correct here — after this, nothing is pending.
      rebuild = "pushd ~/dotfiles/nixos/.config/nixos && git add --all . && sudo nixos-rebuild switch --flake .#${host} && rm -f ~/.local/state/hm-switch-pending && popd";
      # Home-only switch: builds the SAME Home Manager generation the NixOS
      # config defines (no sudo, no bootloader) and activates it in the LIVE
      # session. It does NOT persist: home-manager-${user}.service re-activates
      # the generation baked into the current *system* generation at boot, so
      # anything applied here is thrown away on reboot until `rebuild` runs.
      # The stamp records what was activated so hm-drift-guard.nix can report
      # the revert instead of letting it pass silently.
      # Backup env vars mirror home-manager.backupFileExtension/overwriteBackup,
      # which otherwise only apply when activation runs via home-manager-<user>.service.
      hm-switch = "pushd ~/dotfiles/nixos/.config/nixos && git add --all . && nix build .#nixosConfigurations.${host}.config.home-manager.users.matth.home.activationPackage -o /tmp/hm-activation-result && HOME_MANAGER_BACKUP_EXT=hm-backup HOME_MANAGER_BACKUP_OVERWRITE=1 /tmp/hm-activation-result/activate && mkdir -p ~/.local/state && { readlink -f /tmp/hm-activation-result; cat /proc/sys/kernel/random/boot_id; } > ~/.local/state/hm-switch-pending && print -P '%F{yellow}hm-switch applied to the LIVE session only — reverted at next boot until you run: rebuild%f' && popd";
      rebuildu = "pushd ~/dotfiles/nixos/.config/nixos && cp flake.lock flake.$(date +%Y-%m-%d).lock && git add --all . && sudo nix flake update --flake ./flake.nix ; sudo nixos-rebuild switch --upgrade --flake .#${host} && popd";
      link-agent-md = "ln -sfn AGENTS.md GEMINI.md && ln -sfn AGENTS.md CLAUDE.md";
      # testing = "echo \"sudo nixos-rebuild switch --flake .#${host}\"";
      # rebuild = "git add . && sudo nixos-rebuild switch --flake .#${host}";
      # rebuildu = "git add . && sudo nixos-rebuild switch --upgrade --flake .#${host}";
      nix-flake-update = "sudo nix flake update ~/dotfiles/nixos/.config/nixos#";
      nix-clean = "sudo nix-collect-garbage && sudo nix-collect-garbage -d && sudo rm /nix/var/nix/gcroots/auto/* && nix-collect-garbage && nix-collect-garbage -d";

      # Git

      ga = "git add";
      gaa = "git add --all";
      gst = "git stash";
      gs = "git status";
      gb = "git branch";
      gm = "git merge";
      gpl = "git pull";
      gplo = "git pull origin";
      gps = "git push";
      gpst = "git push --follow-tags";
      gpso = "git push origin";
      gc = "git commit";
      gcm = "git commit -m";
      gcma = "git add --all && git commit -m";
      gtag = "git tag -ma";
      gch = "git checkout";
      gchb = "git checkout -b";
      gcoe = "git config user.email";
      gcon = "git config user.name";
      glazy = "git add --all ; git commit -am \"This is an automated commit by $USER because they were too lazy\" ; git pull && git push";
      md2substack = "pandoc -f markdown -t html | wl-copy -t text/html";
      server = "ssh -p 22 matth@server.matthandzel.com";
      serverfs = "sshfs matth@ssh.matthandzel.com:/home/matth/";
      # make transcribe available as a command
      transcribe = "${transcribe_file_script}";
      claude = "claude --permission-mode auto --chrome";

      # move folder to archive with the same name as the folder
      second-brain-archive = "${second-brain-archive-script}";

      # python
      piv = "python -m venv .venv";
      psv = "source .venv/bin/activate";
      transcribe-meeting = "nix run /home/matth/Projects/KnowledgeOperatingSystem/MeetingTranscribe/ -- --diarize --noise-filter";
    };
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };
}
