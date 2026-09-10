{...}: {
  security.rtkit.enable = true;
  security.sudo.enable = true;
  # security.pam.services.swaylock = { };
  # Autologin skips PAM entirely, so gnome-keyring never gets unlocked with
  # the login password; hyprlock (exec-once at session start) is the first
  # real password prompt, so unlock the keyring there instead of a second time.
  security.pam.services.hyprlock = {
    enableGnomeKeyring = true;
  };
}
