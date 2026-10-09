#!/usr/bin/env python3
"""Talks to Dokploy's API for the Dokploy Status widget.

Usage:
  dokploy.py fetch <server-url>
      Prints {"projects": [...]} as JSON: every project with its environments and their
      services (applications, compose stacks and databases) with name, type and status.
  dokploy.py <deploy|start|stop> <server-url> <service-type> <service-id>
      Deploys, starts or stops one service. Types: application, compose, postgres, mysql,
      mariadb, mongo, redis.

The API key is read from the keyring, where the widget's settings page stores it
(secret-tool attributes: service plasma-dokploy, server <server-url>). It is sent in the
x-api-key header, so it never appears on a command line. Only names and statuses are
copied out of Dokploy's responses; database passwords and environment variables are not.
"""
import json
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

DATABASE_TYPES = ("postgres", "mysql", "mariadb", "mongo", "redis")
SERVICE_TYPES = ("application", "compose") + DATABASE_TYPES


def fail(message, code):
    print(message, file=sys.stderr)
    sys.exit(code)


def key_for(server):
    result = subprocess.run(["secret-tool", "lookup", "service", "plasma-dokploy", "server", server],
                            capture_output=True, text=True)
    key = result.stdout.strip()
    if not key:
        fail(f"No API key in the keyring for {server}", 3)
    return key


def call(server, key, endpoint, params=None, body=None):
    url = f"{server}/api/{endpoint}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method="POST" if body is not None else "GET", headers={
        "x-api-key": key,
        "Accept": "application/json",
        "Content-Type": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            raw = response.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        if e.code in (401, 403):
            fail(f"Dokploy rejected the API key ({e.code}). Check the key stored in your keyring.", 4)
        detail = ""
        try:
            detail = json.loads(e.read()).get("message", "")
        except Exception:
            pass
        fail(f"Dokploy returned HTTP {e.code} for {endpoint}" + (f": {detail}" if detail else ""), 5)
    except urllib.error.URLError as e:
        fail(f"Could not reach {server}: {e.reason}", 6)


def fetch(server):
    key = key_for(server)
    projects = []
    for project in call(server, key, "project.all"):
        environments = []
        for env in project.get("environments", []):
            services = []
            for app in env.get("applications") or []:
                services.append({"type": "application", "id": app["applicationId"], "name": app["name"],
                                 "status": app.get("applicationStatus")})
            for compose in env.get("compose") or []:
                services.append({"type": "compose", "id": compose["composeId"], "name": compose["name"],
                                 "status": compose.get("composeStatus")})
            for db_type in DATABASE_TYPES:
                for db in env.get(db_type) or []:
                    db_id = db[f"{db_type}Id"]
                    detail = call(server, key, f"{db_type}.one", {f"{db_type}Id": db_id}) or {}
                    services.append({"type": db_type, "id": db_id, "name": detail.get("name", db_type),
                                     "status": detail.get("applicationStatus")})
            environments.append({"id": env["environmentId"], "name": env["name"], "services": services})
        projects.append({"id": project["projectId"], "name": project["name"], "environments": environments})
    print(json.dumps({"projects": projects}))


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "fetch":
        fetch(sys.argv[2].rstrip("/"))
    elif len(sys.argv) == 5 and sys.argv[1] in ("deploy", "start", "stop") and sys.argv[3] in SERVICE_TYPES:
        action, server, service_type, service_id = sys.argv[1], sys.argv[2].rstrip("/"), sys.argv[3], sys.argv[4]
        call(server, key_for(server), f"{service_type}.{action}", body={f"{service_type}Id": service_id})
    else:
        fail(__doc__, 2)


if __name__ == "__main__":
    main()
