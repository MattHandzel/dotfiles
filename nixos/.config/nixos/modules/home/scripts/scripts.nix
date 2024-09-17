{ pkgs, ... }: 
let
  # Helper function to create a shell script bin

removeShExtension = str: builtins.replaceStrings [".sh"] [""] str;
makeShellScriptBin = script: pkgs.writeShellScriptBin ((removeShExtension (builtins.baseNameOf script)) ) (builtins.readFile script);

  # List of shell scripts
  shellScripts = [
    ./scripts/wall-change.sh
    ./scripts/wallpaper-picker.sh
    ./scripts/runbg.sh
    ./scripts/music.sh
    ./scripts/lofi.sh
    ./scripts/toggle_blur.sh
    ./scripts/toggle_oppacity.sh
    ./scripts/maxfetch.sh
    ./scripts/compress.sh
    ./scripts/extract.sh
    ./scripts/shutdown-script.sh
    ./scripts/keybinds.sh
    ./scripts/vm-start.sh
    ./scripts/ascii.sh
    ./scripts/record.sh
    ./scripts/brightness.sh
    ./scripts/secondary-monitor-update.sh
    ./scripts/tmux-sessionizer.sh
    ./scripts/focus_app.sh
    ./scripts/run-nix-shell-on-new-tmux-session.sh
    ./scripts/notify-if-command-is-successful.sh
    ./scripts/switch-workspace-to-other-monitor.sh
    ./scripts/run-command-based-on-type-of-workspace.sh
    ./scripts/kill-window-and-switch.sh
    ./scripts/take-note.sh
    ./scripts/calendar.sh
    ./scripts/quick-capture.sh
    ./scripts/copy-to-clipboard.sh
  ];

  # Create shell script bins
  shellScriptBins = map makeShellScriptBin shellScripts;

in {
  home.packages = with pkgs; shellScriptBins ++ [
    bc # for brightness script
    ddcutil # for brightness script
    gum # run-nix-shell-on-new-tmux-session requires this
    jq
    nmap # for looking at devices on the wifi

    calcurse # for calendar script
    vdirsyncer # for calendar script



    # quick capture
    zenity
    wl-clipboard
    grim
    wf-recorder
    alsa-utils  # for arecord
    ffmpeg

  ];
}

