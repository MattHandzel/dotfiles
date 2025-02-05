{pkgs, ...}: {
  home.packages = with pkgs; [todoist pass];
}
