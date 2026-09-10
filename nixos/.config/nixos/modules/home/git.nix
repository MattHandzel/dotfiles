{pkgs, ...}: {
  programs.git = {
    enable = true;

    userName = "MattHandzel";
    userEmail = "handzelmatthew@gmail.com";

    extraConfig = {
      init.defaultBranch = "main";
      credential.helper = "store";
      # `git stauts` -> git already knows you meant `status`; "prompt" makes it
      # offer to run the corrected command instead of just printing the hint.
      # Native (git >= 2.38), so no fragile stderr-parsing wrapper around git.
      help.autocorrect = "prompt";
    };
  };

  home.packages = [pkgs.gh pkgs.git-lfs];
}
