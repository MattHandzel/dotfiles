{pkgs, ...}: {
  services.mako = {
    enable = true;
    settings = {
      font = "Fira Code 10";
      margin = "10";
    };
  };
}
