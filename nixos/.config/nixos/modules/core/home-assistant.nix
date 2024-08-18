{pkgs, ...}:

{

    services.home-assistant = {
    enable = true;
    package = pkgs.home-assistant;
    extraComponents = [
      # Components required to complete the onboarding
      "esphome"
      "met"
      "radio_browser"
    ];
    configDir = "/var/lib/home-assistant";
    config = {
      # Includes dependencies for a basic setup
      # https://www.home-assistant.io/integrations/default_config/
      default_config = {};
    };
  };


  }


