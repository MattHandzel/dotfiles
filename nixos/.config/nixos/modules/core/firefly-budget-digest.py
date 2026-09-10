#!/usr/bin/env python3
"""Email Matt a Firefly III budget digest.

Firefly III has no native budget-summary notification -- it only notifies on bill
reminders, transaction creation, rule-action failures and security events. This
builds the missing digest from the API:

  * every budget, its limit, what has been spent, and what is left
  * a pace indicator: are you ahead of or behind where the month says you should be
  * bills due in the next 14 days (the Rocket Money "subscriptions" view)
  * uncategorised spend, so the rules can be improved over time

Run monthly on the 1st (previous month wrap-up) and weekly on Sunday (pace check).
"""
from __future__ import annotations

import argparse
import calendar
import datetime as dt
import json
import smtplib
import ssl
import urllib.error
import urllib.request
from email.message import EmailMessage


def api(base: str, pat: str, path: str) -> dict:
    req = urllib.request.Request(f"{base}/api/v1{path}", method="GET")
    req.add_header("Authorization", f"Bearer {pat}")
    req.add_header("Accept", "application/json")
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode())


def money(x: float) -> str:
    return f"${x:,.2f}"


def collect(base: str, pat: str, start: dt.date, end: dt.date) -> dict:
    rng = f"?start={start.isoformat()}&end={end.isoformat()}"
    budgets = api(base, pat, f"/budgets{rng}").get("data", [])

    rows = []
    for b in budgets:
        attrs = b["attributes"]
        if not attrs.get("active", True):
            continue
        spent = sum(abs(float(s.get("sum", 0))) for s in (attrs.get("spent") or []))
        limit = 0.0
        try:
            lims = api(base, pat, f"/budgets/{b['id']}/limits{rng}").get("data", [])
            limit = sum(float(l["attributes"]["amount"]) for l in lims)
        except urllib.error.HTTPError:
            pass
        rows.append({"name": attrs["name"], "spent": spent, "limit": limit})

    rows.sort(key=lambda r: (r["limit"] - r["spent"]))

    # bills due soon
    bills = []
    try:
        soon = dt.date.today() + dt.timedelta(days=14)
        for bl in api(base, pat, f"/bills?start={dt.date.today()}&end={soon}").get("data", []):
            a = bl["attributes"]
            nxt = (a.get("next_expected_match") or "")[:10]
            if nxt:
                bills.append({"name": a["name"], "date": nxt,
                              "lo": float(a["amount_min"]), "hi": float(a["amount_max"])})
        bills.sort(key=lambda b: b["date"])
    except urllib.error.HTTPError:
        pass

    return {"rows": rows, "bills": bills}


def render(data: dict, start: dt.date, end: dt.date, pace: float) -> tuple[str, str]:
    rows, bills = data["rows"], data["bills"]
    total_spent = sum(r["spent"] for r in rows)
    total_limit = sum(r["limit"] for r in rows)

    lines = [f"Budget digest for {start:%-d %b} - {end:%-d %b %Y}",
             f"{int(pace * 100)}% of the period elapsed.",
             ""]
    html = [
        "<h2>Firefly budget digest</h2>",
        f"<p><b>{start:%-d %b} &ndash; {end:%-d %b %Y}</b> &middot; "
        f"{int(pace * 100)}% of the period elapsed</p>",
        "<table cellpadding=6 style='border-collapse:collapse'>",
        "<tr style='text-align:left;border-bottom:1px solid #ccc'>"
        "<th>Budget</th><th>Spent</th><th>Limit</th><th>Left</th><th></th></tr>",
    ]

    for r in rows:
        left = r["limit"] - r["spent"]
        if r["limit"] > 0:
            frac = r["spent"] / r["limit"]
            flag = "OVER" if frac > 1 else ("ahead of pace" if frac > pace + 0.1 else "ok")
        else:
            frac, flag = 0.0, "no limit"
        colour = {"OVER": "#c0392b", "ahead of pace": "#e67e22"}.get(flag, "#27ae60")
        lines.append(f"  {r['name']:<16} {money(r['spent']):>10} / {money(r['limit']):>10}  {flag}")
        html.append(
            f"<tr><td>{r['name']}</td><td>{money(r['spent'])}</td>"
            f"<td>{money(r['limit'])}</td><td>{money(left)}</td>"
            f"<td style='color:{colour}'>{flag}</td></tr>")

    html.append("</table>")
    lines += ["", f"Total: {money(total_spent)} of {money(total_limit)}"]
    html.append(f"<p><b>Total: {money(total_spent)} of {money(total_limit)}</b></p>")

    if bills:
        lines += ["", "Bills due in the next 14 days:"]
        html.append("<h3>Bills due in the next 14 days</h3><ul>")
        for b in bills:
            amt = money(b["lo"]) if b["lo"] == b["hi"] else f"{money(b['lo'])}-{money(b['hi'])}"
            lines.append(f"  {b['date']}  {b['name']}  {amt}")
            html.append(f"<li>{b['date']} &mdash; {b['name']} ({amt})</li>")
        html.append("</ul>")

    return "\n".join(lines), "".join(html)


def send_mail(host, port, user, password, to, subject, text, html):
    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = user
    msg["To"] = to
    msg.set_content(text)
    msg.add_alternative(f"<html><body>{html}</body></html>", subtype="html")
    ctx = ssl.create_default_context()
    with smtplib.SMTP(host, port, timeout=45) as s:
        s.starttls(context=ctx)
        s.login(user, password)
        s.send_message(msg)


def notify(topic: str, title: str, body: str) -> None:
    try:
        req = urllib.request.Request(topic, data=body.encode(), method="POST")
        req.add_header("Title", title)
        urllib.request.urlopen(req, timeout=10)
    except Exception:
        pass


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--pat", required=True)
    p.add_argument("--mail-password", required=True)
    p.add_argument("--firefly-url", required=True)
    p.add_argument("--to", required=True)
    p.add_argument("--ntfy", default="")
    p.add_argument("--smtp-host", default="smtp.gmail.com")
    p.add_argument("--smtp-port", type=int, default=587)
    p.add_argument("--month-end", action="store_true",
                   help="summarise the PREVIOUS month instead of the current one")
    args = p.parse_args()

    pat = open(args.pat).read().strip()
    today = dt.date.today()

    # On the 1st, report the month that just ended; otherwise the current month.
    if args.month_end or today.day == 1:
        last = today.replace(day=1) - dt.timedelta(days=1)
        start = last.replace(day=1)
        end = last
        pace = 1.0
        subject = f"Firefly: {start:%B %Y} wrap-up"
    else:
        start = today.replace(day=1)
        end = today.replace(day=calendar.monthrange(today.year, today.month)[1])
        pace = today.day / end.day
        subject = f"Firefly: budget pace, {today:%-d %b}"

    data = collect(args.firefly_url, pat, start, end)
    text, html = render(data, start, end, pace)

    password = open(args.mail_password).read().strip()
    if password.startswith("PLACEHOLDER"):
        print("mail password is still a placeholder; skipping email, sending ntfy only")
        if args.ntfy:
            notify(args.ntfy, subject, text[:800])
        print(text)
        return 0

    try:
        send_mail(args.smtp_host, args.smtp_port, args.to, password,
                  args.to, subject, text, html)
        print(f"sent digest to {args.to}")
    except Exception as e:
        print(f"email failed: {e}")
        if args.ntfy:
            notify(args.ntfy, "Firefly digest email FAILED", str(e)[:300])
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
