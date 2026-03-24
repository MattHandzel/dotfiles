{
  lib,
  pkgs,
  ...
}: let
  sharedVariables = import ../../shared_variables.nix;
  relay = {
    nickname = "MattsHomeRelay";
    contactInfo = "handzelmatthew@gmail.com";
    orPort = 9001;
    dirPort = null;
    bandwidthRate = "1 MBytes";
    bandwidthBurst = "5 MBytes";
    exitPolicy = ["reject *:*"];
  };
  mkPorts =
    (lib.optional (relay.orPort != null) relay.orPort)
    ++ (lib.optional (relay.dirPort != null) relay.dirPort);
in {
  # environment.systemPackages = lib.mkAfter [pkgs.nyx];
  #
  #   networking.firewall.allowedTCPPorts = lib.mkAfter mkPorts;
  #
  #   services.tor = {
  #     enable = true;
  #     client.enable = true;
  #     openFirewall = true;
  #     relay = {
  #       enable = true;
  #       nickname = relay.nickname;
  #       contactInfo = relay.contactInfo;
  #       orPort = relay.orPort;
  #       dirPort = relay.dirPort;
  #       bandwidthRate = relay.bandwidthRate;
  #       bandwidthBurst = relay.bandwidthBurst;
  #       exitPolicy = relay.exitPolicy;
  #       gaurdRelay
  #     };
  #   };
}
