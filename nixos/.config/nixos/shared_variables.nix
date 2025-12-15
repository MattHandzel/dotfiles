{
  # This is a list of applications that have a similar behavior, i.e. there is only 1 of them in existence (most of the time), i want them to each be on a separate workspace, don't show that workspace in waybar
  # distractions "spotify"
  singletonApplications = ["calendar.google.com" "reclaim" "cura" "obsidian" "slack" "btop" "notetaker" "nautilus" "whatsapp-for-linux" "io.github.alainm23.planify" "anki" "planify" "PrusaSlicer" "discord" "thunderbird" "gimp" "yazi" "vit-todo" "gemini.google.com" "beeper"];
  rootDirectory = "/home/matth/dotfiles/nixos/.config/nixos/"; #builtins.toString (builtins.path {path = ./.;});
  serverIpAddress = "97.223.175.122"; #
  # home ip address: 97.223.175.122
  # 76.191.29.237
}
