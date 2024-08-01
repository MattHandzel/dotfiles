{pkgs}:

# This script will look at all of the files in the current directory and save all the ones that end with .nix, if there is more than 1 that ends with .nix it will ask the user which one to pick
pkgs.writeShellScriptBin "source_nix_files_after_cd" ''
  #!/usr/bin/env bash
  ls | grep -E '\.nix$' > /dev/null
  if [ $? -ne 0 ]; then
    echo "No nix files found"
    exit 1
  fi

  if [ $(ls | grep -E '\.nix$' | wc -l) -gt 1 ]; then
    echo "Multiple nix files found, please select one"
    select file in $(ls | grep -E '\.nix$'); do
      if [ -n "$file" ]; then
        break
      fi
    done
  else
    file=$(ls | grep -E '\.nix$')
  fi

  nix-shell --run fish $file

  ''
