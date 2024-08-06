{

# This is a list of applications that have a similar behavior, i.e. there is only 1 of them in existence (most of the time), i want them to each be on a separate workspace, don't show that workspace in waybar
  singletonApplications = ["discord" "spotify" "morgen" "cura" "obsidian" "thunderbird" "slack"];
  rootDirectory = "~/dotfiles/nixos/.config/nixos/"; #builtins.toString (builtins.path {path = ./.;});
  }
