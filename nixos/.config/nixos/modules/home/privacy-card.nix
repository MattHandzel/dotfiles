{
  osConfig,
  pkgs,
  ...
}: let
  # Scaffolding for the agent-issuable-capped-virtual-card half of the "shopping
  # harness" (the non-sensitive part: no account creation, no login, no bank
  # data — just calling the Privacy.com card-issuing API with a key Matt
  # generates himself). See modules/home/scripts/scripts/privacy_card.py for
  # the CLI and its full runbook (auth header, sops steps, Bitwarden flow).
  #
  # Built from the sops symlink root rather than declared as a sops secret:
  # sops-nix validates declared secrets against the encrypted file at BUILD
  # time, so declaring one that has no value yet makes the configuration
  # unbuildable (there is no `optional = true`). This still avoids hardcoding
  # /run/secrets — on darwin that path only exists as a firmlink after the
  # first reboot, and defaultSymlinkPath is whatever sops-nix actually chose.
  # See the note in modules/core/sops.nix for how to provision the key.
  # The directory is taken from a secret that IS declared, rather than from a
  # sops-nix option name (`sops.defaultSymlinkPath` does not exist in the
  # pinned version) or a hardcoded /run/secrets (on darwin that only exists as
  # a firmlink after the first reboot). Whatever directory sops-nix chose for
  # linear_api_key is where privacy_api_key will appear once it is provisioned.
  keyFile = "${builtins.dirOf osConfig.sops.secrets.linear_api_key.path}/privacy_api_key";
in {
  home.packages = [
    (pkgs.writeShellApplication {
      name = "privacy_card";
      runtimeInputs = [pkgs.python3];
      text = ''
        key_file="${keyFile}"
        if [ -r "$key_file" ]; then
          PRIVACY_API_KEY="$(cat "$key_file")"
          export PRIVACY_API_KEY
        fi
        exec python3 ${./scripts/scripts/privacy_card.py} "$@"
      '';
    })
  ];
}
