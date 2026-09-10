#!/usr/bin/env python3
"""privacy_card — issue/close/list capped virtual cards via the Privacy.com API.

This is scaffolding for Matt's "shopping harness": an agent can issue a
SINGLE_USE virtual card with a hard spend cap for one purchase, without ever
touching Matt's real card, bank login, or SSN. It does NOT create Privacy.com
accounts, does NOT log in anywhere, and does NOT handle bank-linking — it only
calls the card-issuing API with a key Matt generates himself in the Privacy.com
dashboard.

AUTH
  Reads the key from the env var PRIVACY_API_KEY (never hardcode a key here).
  Per the Privacy.com API reference (https://docs.privacy.com/reference), the
  key is sent as a plain `Authorization: <API_KEY>` header (NOT "Bearer ..." and
  NOT "api-key ...") — Privacy.com's own docs/examples show the raw key as the
  header value. VERIFY this against the live reference before first real use
  (see BLOCKER note below) since this script was written without the ability to
  fetch docs.privacy.com in this environment.

BASE URL
  PRIVACY_API_BASE env var, defaulting to production: https://api.privacy.com
  Sandbox: https://sandbox.privacy.com

SOPS / SECRET WIRING (see modules/core/sops.nix + modules/home/privacy-card.nix)
  PRIVACY_API_KEY is meant to be sourced from the sops secret `privacy_api_key`,
  materialized at /run/secrets/privacy_api_key. This script itself just reads
  the env var — the Nix wrapper is responsible for exporting
  PRIVACY_API_KEY="$(cat /run/secrets/privacy_api_key)" before exec'ing this
  script (see modules/home/privacy-card.nix). Matt drops in the real key with:

    sops secrets/secrets.yaml
    # add a line:  privacy_api_key: <the real key>
    # save/quit — sops re-encrypts the file with the age recipients already
    # configured in .sops.yaml. Then rebuild (home-manager switch / rebuild).

  Until that key exists, /run/secrets/privacy_api_key won't be present and
  this script will exit with a clear "PRIVACY_API_KEY not set" error — that is
  expected and NOT a bug.

BITWARDEN CREDENTIAL-STORE FLOW (for new-account credentials this harness may
later create, e.g. a merchant account paid for with one of these cards)
  1. Matt runs `bw unlock` in his own terminal and exports the returned
     BW_SESSION into his shell (`export BW_SESSION="..."`).
  2. With BW_SESSION set, an agent can run `bw generate` to produce a strong
     password and `bw create item ...` (or `bw get`/`bw edit`) to store the new
     account's credentials in the vault — using the CLI, not the vault UI.
  3. The agent NEVER sees or requests Matt's Bitwarden master password; BW_SESSION
     is a scoped, revocable unlock token that only Matt can mint.
  This script does not implement Bitwarden calls itself — it is documentation
  for the harness workflow this card-issuing tool plugs into.

USAGE
  privacy_card issue <memo> <amount_usd> [--duration TRANSACTION|MONTHLY]
  privacy_card close <token>
  privacy_card list
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.request

DEFAULT_BASE = "https://api.privacy.com"


def api_base() -> str:
    return os.environ.get("PRIVACY_API_BASE", DEFAULT_BASE).rstrip("/")


def api_key() -> str:
    key = os.environ.get("PRIVACY_API_KEY")
    if not key:
        print(
            "privacy_card: PRIVACY_API_KEY is not set.\n"
            "  Set it directly for a one-off run, or (preferred) wire it via the\n"
            "  sops secret 'privacy_api_key' -> /run/secrets/privacy_api_key\n"
            "  (see modules/home/privacy-card.nix and the header of this file).",
            file=sys.stderr,
        )
        sys.exit(1)
    return key


def request(method: str, path: str, body: dict | None = None) -> dict:
    url = f"{api_base()}{path}"
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", api_key())
    req.add_header("Content-Type", "application/json")
    req.add_header("Accept", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            raw = resp.read()
    except urllib.error.HTTPError as e:
        raw = e.read()
        print(
            f"privacy_card: API error {e.code} {e.reason}: {raw.decode(errors='replace')}",
            file=sys.stderr,
        )
        sys.exit(2)
    except urllib.error.URLError as e:
        print(f"privacy_card: network error contacting {url}: {e.reason}", file=sys.stderr)
        sys.exit(2)
    if not raw:
        return {}
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        print(f"privacy_card: non-JSON response from API: {raw!r}", file=sys.stderr)
        sys.exit(2)


def cmd_issue(args: argparse.Namespace) -> None:
    spend_limit_cents = round(args.amount_usd * 100)
    body = {
        "type": "SINGLE_USE",
        "memo": args.memo,
        "spend_limit": spend_limit_cents,
        "spend_limit_duration": args.duration,
    }
    card = request("POST", "/v1/card", body)
    print(f"token:      {card.get('token')}")
    print(f"pan:        {card.get('pan')}")
    print(f"exp_month:  {card.get('exp_month')}")
    print(f"exp_year:   {card.get('exp_year')}")
    print(f"cvv:        {card.get('cvv')}")
    print(f"memo:       {card.get('memo')}")
    print(f"spend_limit: ${spend_limit_cents / 100:.2f} ({args.duration})")
    print(f"state:      {card.get('state')}")


def cmd_close(args: argparse.Namespace) -> None:
    body = {"card_token": args.token, "state": "CLOSED"}
    card = request("PUT", "/v1/card", body)
    print(f"token: {card.get('token')}  state: {card.get('state')}")


def cmd_list(args: argparse.Namespace) -> None:
    resp = request("GET", "/v1/card?state=OPEN&page_size=50")
    cards = resp.get("data", resp if isinstance(resp, list) else [])
    if not cards:
        print("no open cards")
        return
    for card in cards:
        print(
            f"{card.get('token')}\t{card.get('memo') or '-'}\t"
            f"${card.get('spend_limit', 0) / 100:.2f}\t"
            f"...{card.get('last_four', card.get('pan', ''))[-4:]}"
        )


def main() -> None:
    parser = argparse.ArgumentParser(prog="privacy_card", description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    p_issue = sub.add_parser("issue", help="issue a new single-use capped card")
    p_issue.add_argument("memo", help="human-readable label for the card")
    p_issue.add_argument("amount_usd", type=float, help="spend cap in USD, e.g. 42.50")
    p_issue.add_argument(
        "--duration",
        choices=["TRANSACTION", "MONTHLY"],
        default="TRANSACTION",
        help="spend_limit_duration (default: TRANSACTION — cap applies per single charge)",
    )
    p_issue.set_defaults(func=cmd_issue)

    p_close = sub.add_parser("close", help="permanently close a card")
    p_close.add_argument("token", help="card token returned by `issue`/`list`")
    p_close.set_defaults(func=cmd_close)

    p_list = sub.add_parser("list", help="list open cards")
    p_list.set_defaults(func=cmd_list)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
