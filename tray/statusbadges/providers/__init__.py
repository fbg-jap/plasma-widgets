"""All providers register themselves in `registry` when imported."""
from statusbadges.providers.base import Field, Provider, registry
from statusbadges.providers import (bugsink, docker, dokploy, githubaccount,  # noqa: F401  (registration)
                                    githubstatus, prtg)

__all__ = ["Field", "Provider", "registry"]
