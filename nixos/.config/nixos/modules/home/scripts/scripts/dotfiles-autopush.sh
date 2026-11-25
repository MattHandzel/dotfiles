#!/usr/bin/env bash
# dotfiles-autopush: commit and push ~/dotfiles changes that have sat untouched
# for QUIET minutes, so the Redwood laptop's dotfiles-sync picks them up.
# Matt, 2026-11-25: "i added ;scfo on this computer but it wasn't synced to my
# work one. solve this problem" (the edit had never been committed).
#
# Safety, every pass:
#   - only files unchanged for QUIET minutes (default 30), so half-done edits wait
#   - tracked changes, plus new .nix/.lua/.sh/.py/.yml/.toml files under nixos/,
#     nvim/, hammerspoon/ (other new files are left alone)
#   - a temporary git index: whatever is staged in the real one is not swept in
#   - both Macs' configs must still evaluate, or nothing is pushed
#   - gitleaks on the diff, or nothing is pushed
# Exits non-zero when a pass fails (launchd job dotfiles-autopush).
set -euo pipefail
REPO="$HOME/dotfiles"
QUIET="${QUIET:-30}"
BRANCH="$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"
STAMP="$HOME/.local/state/dotfiles-autopush.ok"
cd "$REPO"

files=()
now=$(date +%s)
while IFS= read -r -d '' entry; do
  st="${entry:0:2}"; f="${entry:3}"
  case "$st" in
    R*|C*) read -r -d '' _ || true ;;  # rename: next field is the old path
  esac
  if [ "$st" = "??" ]; then
    case "$f" in
      nixos/*|nvim/*|hammerspoon/*) ;;
      *) continue ;;
    esac
    case "$f" in *.nix|*.lua|*.sh|*.py|*.yml|*.yaml|*.toml) ;; *) continue ;; esac
  fi
  if [ -e "$f" ]; then
    m=$(/usr/bin/stat -f %m "$f")
    [ $(( (now - m) / 60 )) -ge "$QUIET" ] || continue
  fi
  files+=("$f")
done < <(git status --porcelain -z --untracked-files=all)

if [ ${#files[@]} -eq 0 ]; then date -Iseconds > "$STAMP"; echo "$(date -Iseconds) nothing quiet to push"; exit 0; fi

idx="$(mktemp)"; trap 'rm -f "$idx"' EXIT
export GIT_INDEX_FILE="$idx"
git read-tree HEAD
git add -A -- "${files[@]}"
tree=$(git write-tree)
if [ "$tree" = "$(git rev-parse HEAD^{tree})" ]; then unset GIT_INDEX_FILE; date -Iseconds > "$STAMP"; exit 0; fi

if ! git diff HEAD "$tree" | gitleaks stdin --no-banner --redact -l error >/dev/null; then
  echo "gitleaks flagged the pending dotfiles changes; nothing pushed" >&2; exit 1
fi

# Both hosts must evaluate from exactly this tree before anything is pushed.
commit=$(git commit-tree "$tree" -p HEAD -m "autopush: $(printf '%s\n' "${files[@]}" | sed 's#.*/##' | sort -u | head -6 | paste -sd, -)

Changes on matts-mac left untouched for ${QUIET}+ min, pushed by dotfiles-autopush.")
unset GIT_INDEX_FILE
if printf '%s\n' "${files[@]}" | grep -q '^nixos/'; then
  for h in matts-mac redwood-mac; do
    if ! nix eval --raw "git+file://$REPO?dir=nixos/.config/nixos&rev=$commit#darwinConfigurations.$h.system.drvPath" >/dev/null 2>"$HOME/.local/state/dotfiles-autopush.eval.log"; then
      echo "$h no longer evaluates with the pending changes; nothing pushed (see ~/.local/state/dotfiles-autopush.eval.log)" >&2
      exit 1
    fi
  done
fi
if [ "${DRY_RUN:-0}" = 1 ]; then printf "would push %s\n" "${files[@]}"; exit 0; fi
git update-ref "refs/heads/$BRANCH" "$commit" HEAD
git reset -q -- "${files[@]}"
git push -q origin "$BRANCH"
date -Iseconds > "$STAMP"
echo "$(date -Iseconds) pushed $(git rev-parse --short HEAD): ${#files[@]} files"
