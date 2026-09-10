{pkgs, ...}: let
  # Scaffolding for the agent-issuable-capped-virtual-card half of the "shopping
  # harness" (the non-sensitive part: no account creation, no login, no bank
  # data — just calling the Privacy.com card-issuing API with a key Matt
  # generates himself). See modules/home/scripts/scripts/privacy_card.py for
  # the CLI and its full runbook (auth header, sops steps, Bitwarden flow).
  #
  # A Privacy.com API key can later be provisioned at
  # /run/secrets/privacy_api_key. Until then this wrapper fails with a clear
  # error rather than making the whole NixOS configuration unbuildable.
  keyFile = "/run/secrets/privacy_api_key";
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
