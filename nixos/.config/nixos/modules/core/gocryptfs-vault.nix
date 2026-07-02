{ pkgs, ... }:
let
  encDir = "$HOME/Obsidian/Main/.private.enc";
  mountDir = "$HOME/Obsidian/Main/private";

  vault-unlock = pkgs.writeShellScriptBin "vault-unlock" ''
    set -u
    ENC=${encDir}
    MNT=${mountDir}

    if ! [ -d "$ENC" ]; then
      ${pkgs.libnotify}/bin/notify-send -u critical "Vault" "Not initialized at $ENC. Run: gocryptfs -init \"$ENC\""
      exit 1
    fi

    if mountpoint -q "$MNT" 2>/dev/null; then
      ${pkgs.libnotify}/bin/notify-send "Vault" "Already unlocked at $MNT"
      exit 0
    fi

    mkdir -p "$MNT"

    PW=$(${pkgs.zenity}/bin/zenity --password --title="Unlock Obsidian private vault" 2>/dev/null) || exit 1

    if printf '%s' "$PW" | ${pkgs.gocryptfs}/bin/gocryptfs -q "$ENC" "$MNT"; then
      unset PW
      ${pkgs.libnotify}/bin/notify-send "Vault" "Unlocked: $MNT"
    else
      unset PW
      ${pkgs.libnotify}/bin/notify-send -u critical "Vault" "Unlock failed"
      exit 1
    fi
  '';

  vault-lock = pkgs.writeShellScriptBin "vault-lock" ''
    set -u
    MNT=${mountDir}

    if ! mountpoint -q "$MNT" 2>/dev/null; then
      ${pkgs.libnotify}/bin/notify-send "Vault" "Already locked"
      exit 0
    fi

    if ${pkgs.fuse}/bin/fusermount -u "$MNT"; then
      ${pkgs.libnotify}/bin/notify-send "Vault" "Locked"
    else
      ${pkgs.libnotify}/bin/notify-send -u critical "Vault" "Lock failed (file still open?)"
      exit 1
    fi
  '';
in {
  programs.fuse.userAllowOther = true;

  environment.systemPackages = [
    pkgs.gocryptfs
    vault-unlock
    vault-lock
  ];
}
