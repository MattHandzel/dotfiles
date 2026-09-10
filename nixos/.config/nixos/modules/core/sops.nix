{
  inputs,
  config,
  username,
  ...
}: {
  imports = [
    inputs.sops-nix.nixosModules.sops
  ];

  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    defaultSopsFormat = "yaml";

    age.sshKeyPaths = ["/home/${username}/.ssh/id_ed25519"];

    secrets.gcal_client_secret = {
      owner = username;
    };

    # Linear personal API key (lin_api_…) for the desktop notification poller.
    # Materialized at /run/secrets/linear_api_key; consumed by modules/home/linear-notify.nix.
    secrets.linear_api_key = {
      owner = username;
    };

    # privacy_api_key is deliberately NOT declared here.
    #
    # sops-nix validates every declared secret against the encrypted file at
    # BUILD time ("secret privacy_api_key ... is not valid: the key
    # 'privacy_api_key' cannot be found"), so declaring a secret that has no
    # value yet makes the whole configuration unbuildable. There is no
    # `optional = true`.
    #
    # modules/home/privacy-card.nix therefore builds the path from
    # `osConfig.sops.defaultSymlinkPath` instead — which is the same directory
    # every other secret lands in, correct on both platforms, and does not
    # hardcode /run/secrets. The wrapper checks readability at runtime and
    # fails with a clear message until the key exists.
    #
    # To provision it: `sops secrets/secrets.yaml`, add `privacy_api_key`, then
    # uncomment the block below.
    #
    # secrets.privacy_api_key = {
    #   owner = username;
    # };

    # secrets.todoist_api_key = {
    #   owner = username;
    # };
  };
}
