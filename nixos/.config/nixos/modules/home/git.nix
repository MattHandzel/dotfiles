{ pkgs, ... }: 
{
  programs.git = {
    enable = true;
    
    userName = "MattHandzel";
    userEmail = "handzelmatthew@gmail.com";
    
    extraConfig = { 
      init.defaultBranch = "main";
      credential.helper = "store";
    };
  };

  # home.packages = [ pkgs.gh pkgs.git-lfs ];
}
