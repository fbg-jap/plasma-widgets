"""Small JSON-over-HTTP helper shared by the providers."""
import json
import urllib.error
import urllib.parse
import urllib.request

from statusbadges.model import ProviderError


def request(url: str, headers: dict | None = None, params: dict | list | None = None, body=None,
            method: str | None = None, auth_name: str = "the server") -> object:
    if params:
        url += ("&" if "?" in url else "?") + urllib.parse.urlencode(params, doseq=True)
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method or ("POST" if data is not None else "GET"),
                                 headers={"Accept": "application/json", "Content-Type": "application/json",
                                          "User-Agent": "status-badges", **(headers or {})})
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            raw = response.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        if e.code in (401, 403):
            raise ProviderError(f"{auth_name} rejected the API key ({e.code}). Check the key in the settings.")
        raise ProviderError(f"{auth_name} returned HTTP {e.code}")
    except urllib.error.URLError as e:
        raise ProviderError(f"Could not reach {urllib.parse.urlparse(url).netloc}: {e.reason}")
    except json.JSONDecodeError:
        raise ProviderError(f"{auth_name} sent a response that isn't JSON")
