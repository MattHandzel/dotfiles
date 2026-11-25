#!/usr/bin/env python3
"""Generate a diceware-style passphrase or random-character password.

Usage:
  genpass                 # 6-word passphrase (default)
  genpass -w 7            # 7-word passphrase
  genpass -s _            # use '_' as separator instead of '-'
  genpass -c              # capitalize each word
  genpass -n 5            # print 5 candidates
  genpass --chars         # random-character password instead of passphrase
  genpass --chars -l 24   # 24-character random password
"""
import argparse
import secrets
import string
from pathlib import Path

WORDLIST_PATH = Path.home() / ".local/share/diceware/eff_large_wordlist.txt"


def load_words():
    if not WORDLIST_PATH.exists():
        raise SystemExit(f"wordlist not found at {WORDLIST_PATH}")
    words = []
    for line in WORDLIST_PATH.read_text().splitlines():
        parts = line.split()
        if len(parts) == 2:
            words.append(parts[1])
    return words


def passphrase(words, count, sep, capitalize):
    chosen = [secrets.choice(words) for _ in range(count)]
    if capitalize:
        chosen = [w.capitalize() for w in chosen]
    return sep.join(chosen)


def random_chars(length):
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*-_=+?"
    return "".join(secrets.choice(alphabet) for _ in range(length))


def main():
    parser = argparse.ArgumentParser(description="Generate secure passphrases or passwords.")
    parser.add_argument("-w", "--words", type=int, default=6, help="number of words (default: 6)")
    parser.add_argument("-s", "--sep", default="-", help="word separator (default: '-')")
    parser.add_argument("-c", "--capitalize", action="store_true", help="capitalize each word")
    parser.add_argument("-n", "--num", type=int, default=1, help="number of candidates to print")
    parser.add_argument("--chars", action="store_true", help="generate a random-character password instead")
    parser.add_argument("-l", "--length", type=int, default=20, help="length for --chars mode (default: 20)")
    args = parser.parse_args()

    if args.chars:
        for _ in range(args.num):
            print(random_chars(args.length))
        return

    words = load_words()
    for _ in range(args.num):
        print(passphrase(words, args.words, args.sep, args.capitalize))


if __name__ == "__main__":
    main()
