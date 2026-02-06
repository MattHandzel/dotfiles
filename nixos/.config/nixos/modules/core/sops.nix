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

    secrets.todoist_api_key = {
      owner = username;
    };
  };
}
