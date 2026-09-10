# Home Manager refuses to activate when a path it wants to manage is occupied
# by a foreign SYMLINK: backupFileExtension only rescues regular files
# (check-link-targets.sh guards the backup branch with `! -L "$targetPath"`),
# so a symlink collision always hard-fails the rebuild.
#
# The recurring offender is `systemctl --user enable <unit>`, which drops
# ~/.config/systemd/user/<target>.wants/<unit> symlinks that collide once the
# unit later declares Install.WantedBy declaratively (e.g. lifelog-collector,
# 2026-07-16). Enable-links carry no data, so any foreign symlink sitting
# where the incoming generation will place a file is safe to delete here;
# regular files still take the *.hm-backup path.
{lib, ...}: {
  home.activation.removeForeignSymlinks = lib.hm.dag.entryBefore ["checkLinkTargets"] ''
    newGenFiles="$(readlink -e "$newGenPath/home-files")"
    storeDir="$(readlink -e /nix/store)"
    find "$newGenFiles" \( -type f -o -type l \) -print0 \
      | while IFS= read -r -d "" sourcePath; do
        targetPath="$HOME/''${sourcePath#"$newGenFiles"/}"
        if [ -L "$targetPath" ]; then
          case "$(readlink "$targetPath")" in
            "$storeDir"/*-home-manager-files/*) ;;
            *)
              verboseEcho "Removing foreign symlink '$targetPath' blocking activation"
              run rm "$targetPath"
              ;;
          esac
        fi
      done
  '';
}
