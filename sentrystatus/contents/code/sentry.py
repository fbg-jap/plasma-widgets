#!/usr/bin/env python3
"""Talks to Sentry's web API for the Sentry Status widget.

Usage:
  sentry.py fetch <server-url> <organization> [max-pages]
      Prints {"issues": [...], "counts": {...}, "truncated": bool} as JSON: the organization's
      unresolved issues (most recently seen first, 100 per page) and how many issues are new
      (first seen in the last 24 hours), unresolved, archived and resolved. Counts cover issues
      seen in the last 90 days, Sentry's usual retention.
  sentry.py <resolve|archive> <server-url> <organization> <issue-id>
      Changes one issue.

The auth token is read from the keyring, where the widget's settings page stores it
(secret-tool attributes: service plasma-sentry, server <server-url>). It is sent in the
Authorization header, so it never appears on a command line.
"""
import json
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

ISSUE_FIELDS = ("id", "shortId", "title", "culprit", "level", "firstSeen", "lastSeen", "count", "userCount",
                "permalink")
PERIOD = "90d"
STATUS_FOR_ACTION = {"resolve": {"status": "resolved"}, "archive": {"status": "ignored"}}


def fail(message, code):
    print(message, file=sys.stderr)
    sys.exit(code)


def token_for(server):
    result = subprocess.run(["secret-tool", "lookup", "service", "plasma-sentry", "server", server],
                            capture_output=True, text=True)
    token = result.stdout.strip()
    if not token:
        fail(f"No auth token in the keyring for {server}", 3)
    return token


def request(server, token, path_or_url, method="GET", body=None):
    """Returns (parsed JSON, response headers)."""
    url = path_or_url if path_or_url.startswith("http") else server + path_or_url
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, method=method, data=data, headers={
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
        "Content-Type": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            raw = response.read()   # a bulk change can answer 204 with no body
            return (json.loads(raw) if raw else None), response.headers
    except urllib.error.HTTPError as e:
        if e.code in (401, 403):
            fail(f"Sentry rejected the auth token ({e.code}). Check the token stored in your keyring "
                 "and that it has the event:read and event:write scopes.", 4)
        if e.code == 404:
            fail(f"Sentry has no organization at {url.split('?')[0]}. Check the organization slug.", 5)
        fail(f"Sentry returned HTTP {e.code} for {url.split('?')[0]}", 5)
    except urllib.error.URLError as e:
        fail(f"Could not reach {server}: {e.reason}", 6)


def issues_path(org, query, **params):
    # project=-1: every project the token can see, not only the user's own ones.
    query_string = urllib.parse.urlencode({"project": -1, "statsPeriod": PERIOD, "query": query, **params})
    return f"/api/0/organizations/{urllib.parse.quote(org)}/issues/?{query_string}"


def next_page(headers):
    """The next page's URL from Sentry's Link header, or None."""
    for part in (headers.get("Link") or "").split(","):
        match = re.search(r'<([^>]+)>;\s*rel="next";\s*results="(true|false)"', part)
        if match and match.group(2) == "true":
            return match.group(1)
    return None


def hits(server, token, org, query):
    """How many issues match: Sentry's X-Hits header, read from a one-issue page. Without that
    header, the issues on a full page are counted instead (so at most 100)."""
    results, headers = request(server, token, issues_path(org, query, limit=1))
    try:
        return int(headers.get("X-Hits"))
    except (TypeError, ValueError):
        results, _ = request(server, token, issues_path(org, query, limit=100))
        return len(results or [])


def fetch(server, org, max_pages):
    token = token_for(server)
    issues, url, pages = [], issues_path(org, "is:unresolved", sort="date", limit=100), 0
    unresolved = None
    while url and pages < max_pages:
        results, headers = request(server, token, url)
        if unresolved is None and headers.get("X-Hits"):
            unresolved = int(headers.get("X-Hits"))
        issues += [{**{k: i.get(k) for k in ISSUE_FIELDS}, "project": (i.get("project") or {}).get("name")
                    or (i.get("project") or {}).get("slug")} for i in results]
        url, pages = next_page(headers), pages + 1
    counts = {
        "new": hits(server, token, org, "is:unresolved firstSeen:-24h"),
        "unresolved": unresolved if unresolved is not None else len(issues),
        "archived": hits(server, token, org, "is:ignored"),
        "resolved": hits(server, token, org, "is:resolved"),
    }
    print(json.dumps({"issues": issues, "counts": counts, "truncated": bool(url)}))


def main():
    if len(sys.argv) < 4:
        fail(__doc__, 2)
    command, server, org = sys.argv[1], sys.argv[2].rstrip("/"), sys.argv[3]
    if command == "fetch" and len(sys.argv) <= 5:
        fetch(server, org, int(sys.argv[4]) if len(sys.argv) > 4 else 1)
    elif command in STATUS_FOR_ACTION and len(sys.argv) == 5 and sys.argv[4].isdigit():
        request(server, token_for(server), f"/api/0/organizations/{urllib.parse.quote(org)}/issues/?id={sys.argv[4]}",
                method="PUT", body=STATUS_FOR_ACTION[command])
    else:
        fail(__doc__, 2)


if __name__ == "__main__":
    main()
