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

    # secrets.todoist_api_key = {
    #   owner = username;
    # };
  };
}
