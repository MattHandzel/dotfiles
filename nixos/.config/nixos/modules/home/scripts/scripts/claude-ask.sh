#!/usr/bin/env bash
#
# claude-ask — quick "learn this" launcher for Claude.ai.
#
# Tap the copilot key: pick a mode (explain / examples / word-in-context /
# add context / abstract / connect / challenge / ask anything), then type or
# paste a word, concept, or question. Opens a fresh Claude conversation with
# the request prefilled (via ?q=) so the answer is already generating by the
# time you look at it. The window lands in the dedicated "claude.ai" workspace
# (see shared_variables.nix singletonApplications + the Hyprland window rule).
#
# Mirrors the prompt templates used by the zen-learn-extension context menu
# (~/Projects/zen-learn-extension) so the keyboard flow and the highlight flow
# behave the same.

set -euo pipefail

# ── Step 1: pick a mode ──────────────────────────────────────────────
mode="$(printf '%s\n' \
  "Ask anything" \
  "Explain this deeply" \
  "Word: show me real usage in context" \
  "Give me examples" \
  "Add context (who / what / why)" \
  "Make it abstract / find the principle" \
  "Connect to what I already know" \
  "Steel-man and challenge it" \
  | fuzzel --dmenu --prompt 'Claude  ➜  ')"

[ -z "${mode:-}" ] && exit 0

# ── Step 2: get the subject (word / concept / question) ──────────────
input="$(fuzzel --dmenu --lines 0 --prompt "${mode}  ➜  " </dev/null)"
[ -z "${input:-}" ] && exit 0

# ── Step 3: build the prompt for the chosen mode ─────────────────────
case "$mode" in
"Ask anything")
  prompt="$input"
  ;;
"Explain this deeply")
  prompt="I want to deeply understand the following — not just what it says, but WHY it's true and HOW it works.

1. Explain it as if I understand the basics but not the nuances.
2. What's the mechanism — why does it work the way it does?
3. What's the most common misconception about it?
4. How does it connect to related concepts I might already know?
5. What would change if one key assumption were different?

Subject: \"$input\""
  ;;
"Word: show me real usage in context")
  prompt="Show me how the word/phrase \"$input\" is actually used in context.

1. Give a precise definition (and note any senses it has).
2. Give 6-8 example sentences from DIFFERENT registers and domains (everyday speech, academic, technical, literary, news) so I can see the range of usage.
3. For each, briefly note what nuance or connotation the word carries there.
4. Point out common collocations and any words it's easily confused with.
5. Note any register/formality or regional caveats."
  ;;
"Give me examples")
  prompt="Give me 3-5 concrete, varied examples of the following concept in action. Make them specific and from different domains so I can see the pattern.

For each example:
- Describe the situation concretely (not abstractly).
- Show how the concept applies.
- Note what's similar and different from the other examples.

Concept: \"$input\""
  ;;
"Add context (who / what / why)")
  prompt="I need relevant background context to fully understand the following. Help me understand the references, people, terms, and ideas involved.

- Identify any people, works, or events being referenced (briefly and concretely).
- Explain why each is relevant — what's the connection?
- Define any technical terms or jargon plainly.
- Surface implicit assumptions someone is expected to already know.
- What prerequisite knowledge would help me understand this better?

Subject: \"$input\""
  ;;
"Make it abstract / find the principle")
  prompt="Help me extract the abstract principle or mental model underneath this specific instance. I want the GENERAL pattern, not just this case.

1. State the abstract principle in one sentence.
2. Explain why it works (the mechanism).
3. Give 2 examples from completely different domains where the same principle applies.
4. What are the boundary conditions — when does this principle NOT apply?

Instance: \"$input\""
  ;;
"Connect to what I already know")
  prompt="Help me connect the following to concepts I might already know from other fields. I want to build bridges between domains.

1. What existing mental models or frameworks does this relate to?
2. What's an analogy from a completely different field?
3. Does it contradict or refine anything commonly believed?
4. If you had to teach it using only everyday concepts, how would you explain it?

Subject: \"$input\""
  ;;
"Steel-man and challenge it")
  prompt="I want to stress-test the following claim. Help me think critically about it.

1. What's the strongest version of this argument (steel-man it)?
2. What's the strongest counterargument?
3. What evidence would change my mind?
4. What are the hidden assumptions?
5. Under what conditions would the opposite be true?

Claim: \"$input\""
  ;;
*)
  prompt="$input"
  ;;
esac

# ── Step 4: open Claude with the request prefilled ───────────────────
encoded="$(jq -rn --arg s "$prompt" '$s|@uri')"

exec systemd-run --user --slice=app-webapps.slice --scope -- \
  chromium \
  --app="https://claude.ai/new?q=${encoded}" \
  --user-data-dir="$HOME/.config/chromium-app" \
  --ozone-platform=wayland
