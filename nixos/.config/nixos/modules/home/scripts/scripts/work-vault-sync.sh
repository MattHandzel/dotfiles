#!/usr/bin/env bash
# work-vault-sync: keep ~/Obsidian/Work the same on Matt's personal Mac and the
# Redwood laptop, but only for notes that say they may leave the machine.
#
# A note syncs only when its frontmatter has `classification: AL1`. Untagged,
# AL2 and AL3 notes stay on the Mac they were written on: they are never staged,
# so they never reach the repo (Matt, 2026-11-25: "tag docs as al1 or al2 ... and
# have those be synced but not other things").
#
# Every pass:
#   1. personal Mac only: mirror ~/Obsidian/Main/templates into templates/
#      (templates hold no work content, so they sync without a tag, one way)
#   2. stage every AL1 note; untrack any tracked note that was deleted or is no
#      longer AL1 (the file stays here; the other Mac's copy is removed)
#   3. gitleaks on what's staged, commit, pull --rebase, push
# Exits non-zero on any failure (launchd job work-vault-sync, error collector).
# Doc: ~/Obsidian/Main/areas/second-brain/work-vault.md
set -euo pipefail

DIR="${WORK_VAULT_DIR:-$HOME/Obsidian/Work}"
REMOTE="${WORK_VAULT_REMOTE:-git@github.com:MattHandzel/work-vault.git}"
STAMP="$HOME/.local/state/work-vault-sync.ok"
HOST="$(scutil --get LocalHostName 2>/dev/null || hostname -s)"

# Frontmatter (between the first two --- lines) has classification: AL1.
is_al1() {
  awk 'NR==1 && $0!="---" {exit 1}
       NR>1 && $0=="---" {exit found?0:1}
       NR>1 && tolower($0) ~ /^classification:[ \t]*["'\'']?al1["'\'']?[ \t]*$/ {found=1}
       END {if (NR<2) exit 1}' "$1"
}

mkdir -p "$DIR" "$(dirname "$STAMP")"
cd "$DIR"

if [ ! -d .git ]; then
  tmp="$(mktemp -d)"
  git clone -q "$REMOTE" "$tmp/repo"
  mv "$tmp/repo/.git" .git
  rm -rf "$tmp"
  # Bring down notes this Mac doesn't have; never overwrite a local file.
  git ls-files -d -z | xargs -0 -r git checkout -q --
  git reset -q
fi

git config user.name "Matt Handzel"
git config pull.rebase true

# 1. Templates, from the personal vault only.
if [ -d "$HOME/Obsidian/Main/templates" ] && [ ! -e "$HOME/.config/work-machine" ]; then
  rsync -a --delete "$HOME/Obsidian/Main/templates/" templates/
fi

# 2. Stage AL1 notes and templates; untrack the rest.
while IFS= read -r -d '' f; do
  f="${f#./}"
  if is_al1 "$f"; then git add -- "$f"; fi
done < <(find . -name '*.md' -not -path './.git/*' -not -path './templates/*' -not -path './.obsidian/*' -print0)
[ -d templates ] && [ ! -e "$HOME/.config/work-machine" ] && git add -A -- templates
while IFS= read -r -d '' f; do
  case "$f" in templates/*|.gitignore|README.md) continue ;; esac
  if [ ! -e "$f" ]; then git rm -q --cached -- "$f"
  elif ! is_al1 "$f"; then git rm -q --cached -- "$f"; echo "untracked (no longer AL1): $f"
  fi
done < <(git ls-files -z)

# 3. Secrets check, commit, pull, push.
if ! git diff --cached --quiet; then
  if ! gitleaks git --staged --no-banner --redact -l error . >/dev/null 2>&1 \
     && ! gitleaks protect --staged --no-banner --redact -l error >/dev/null 2>&1; then
    git reset -q
    echo "gitleaks flagged a staged note; nothing committed" >&2
    exit 1
  fi
  git commit -q -m "sync from $HOST $(date +%F\ %H:%M)"
fi
if ! git pull -q --rebase origin main 2>/dev/null; then
  if git rev-parse -q --verify REBASE_HEAD >/dev/null; then
    git rebase --abort
    echo "conflict: a note changed on both Macs; resolve in $DIR (git status)" >&2
    exit 1
  fi
  # Empty remote (first push) is fine; anything else is a failure.
  git ls-remote --exit-code --heads origin main >/dev/null && { echo "pull failed" >&2; exit 1; }
fi
git push -q origin HEAD:main
date -Iseconds > "$STAMP"
echo "$(date -Iseconds) synced $(git ls-files | wc -l | tr -d ' ') files"
