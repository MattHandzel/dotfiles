{pkgs, ...}: {
  programs.git = {
    enable = true;

    settings = {
      credential.helper = "store";
      init.defaultBranch = "main";
      user = {
        email = "handzelmatthew@gmail.com";
        name = "MattHandzel";
      };
    };
  };

  home.packages = with pkgs; [gh git-lfs];
}
