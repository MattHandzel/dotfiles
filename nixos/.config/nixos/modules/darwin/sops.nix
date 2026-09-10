# sops-nix on macOS — the mirror of modules/core/sops.nix.
#
# The age identity is derived from the SSH key, exactly as on the laptop: the
# recipient in .sops.yaml is `ssh-to-age < ~/.ssh/id_ed25519.pub`, so copying
# ~/.ssh/id_ed25519 to the Mac carries the ability to decrypt with it and
# nothing has to be re-encrypted.
#
# IMPORTANT: on macOS /run does not exist until the synthetic.conf firmlink is
# created, which happens at BOOT. So the very first `darwin-rebuild switch`
# lands secrets nowhere useful and the Mac must be rebooted once (Phase 3 step
# 7) before anything can read them. Consumers therefore read
# `osConfig.sops.secrets.<name>.path` instead of hardcoding /run/secrets — see
# modules/home/{linear-notify,privacy-card}.nix.
{
  inputs,
  username,
  ...
}: {
  imports = [inputs.sops-nix.darwinModules.sops];

  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    defaultSopsFormat = "yaml";

    age.sshKeyPaths = ["/Users/${username}/.ssh/id_ed25519"];

    secrets.gcal_client_secret = {
      owner = username;
    };

    # Linear personal API key (lin_api_…) for the desktop notification poller.
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
  };
}
