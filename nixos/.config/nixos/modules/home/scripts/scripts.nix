{pkgs, ...}: let
  wall-change = pkgs.writeShellScriptBin "wall-change" (builtins.readFile ./scripts/wall-change.sh);
  wallpaper-picker = pkgs.writeShellScriptBin "wallpaper-picker" (builtins.readFile ./scripts/wallpaper-picker.sh);
  
  runbg = pkgs.writeShellScriptBin "runbg" (builtins.readFile ./scripts/runbg.sh);
  music = pkgs.writeShellScriptBin "music" (builtins.readFile ./scripts/music.sh);
  lofi = pkgs.writeScriptBin "lofi" (builtins.readFile ./scripts/lofi.sh);
  
  toggle_blur = pkgs.writeScriptBin "toggle_blur" (builtins.readFile ./scripts/toggle_blur.sh);
  toggle_oppacity = pkgs.writeScriptBin "toggle_oppacity" (builtins.readFile ./scripts/toggle_oppacity.sh);
  
  maxfetch = pkgs.writeScriptBin "maxfetch" (builtins.readFile ./scripts/maxfetch.sh);
  
  compress = pkgs.writeScriptBin "compress" (builtins.readFile ./scripts/compress.sh);
  extract = pkgs.writeScriptBin "extract" (builtins.readFile ./scripts/extract.sh);
  
  shutdown-script = pkgs.writeScriptBin "shutdown-script" (builtins.readFile ./scripts/shutdown-script.sh);
  
  show-keybinds = pkgs.writeScriptBin "show-keybinds" (builtins.readFile ./scripts/keybinds.sh);
  
  vm-start = pkgs.writeScriptBin "vm-start" (builtins.readFile ./scripts/vm-start.sh);

  ascii = pkgs.writeScriptBin "ascii" (builtins.readFile ./scripts/ascii.sh);
  
  record = pkgs.writeScriptBin "record" (builtins.readFile ./scripts/record.sh);

  brightness = pkgs.writeScriptBin "brightness" (builtins.readFile ./scripts/brightness.sh);
  secondary_monitor_update = pkgs.writeScriptBin "secondary_monitor_update" (builtins.readFile ./scripts/secondary_monitor_update.sh);
  tmux_sessionizer = pkgs.writeScriptBin "tmux_sessionizer" (builtins.readFile ./scripts/tmux_sessionizer.sh);

  focus_app = pkgs.writeScriptBin "focus_app" (builtins.readFile ./scripts/focus_app.sh);

  run-nix-shell-on-new-tmux-session = pkgs.writeScriptBin "run-nix-shell-on-new-tmux-session" (builtins.readFile ./scripts/run-nix-shell-on-new-tmux-session.sh);

  notify-if-command-is-successful = pkgs.writeScriptBin "notify-if-command-is-successful" (builtins.readFile ./scripts/notify-if-command-is-successful.sh);

in {
  home.packages = with pkgs; [
    wall-change
    wallpaper-picker
    
    runbg
    music
    lofi
  
    toggle_blur
    toggle_oppacity

    maxfetch

    compress
    extract

    shutdown-script
    
    show-keybinds

    vm-start

    ascii

    record
    brightness
    secondary_monitor_update


    bc # for brightness script
    ddcutil # for brightness script
    tmux_sessionizer # to find and attach to tmux sessions
      

    focus_app # foucses and creates apps if not already existing
     run-nix-shell-on-new-tmux-session   
    gum # run-nix-shell-on-new-tmux-session requires this
     notify-if-command-is-successful  
  ];

}
