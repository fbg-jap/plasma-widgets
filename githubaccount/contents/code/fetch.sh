#!/bin/sh
# Prints {"notifications": [...], "graphql": {...}} for the GitHub Account widget.
# Uses the gh CLI's stored login, so the widget never handles a token itself.
# Usage: fetch.sh <account> [mark-read]
# With "mark-read" as the second argument, marks all notifications read first.
set -e

# The first argument picks which gh account to use; empty means gh's active account.
# The account's token is passed to gh in the environment, not on the command line.
if [ -n "$1" ]; then
    GH_TOKEN=$(gh auth token --hostname github.com --user "$1" 2>/dev/null) || {
        echo "gh is not logged in as $1. Run: gh auth login" >&2
        exit 4
    }
    export GH_TOKEN
fi

if [ "$2" = "mark-read" ]; then
    gh api -X PUT notifications --silent
fi

query='{
  viewer {
    login
    pullRequests(states: OPEN, first: 20, orderBy: {field: UPDATED_AT, direction: DESC}) {
      nodes {
        title url number isDraft
        repository { nameWithOwner }
        commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
      }
    }
    repositories(first: 8, orderBy: {field: PUSHED_AT, direction: DESC},
                 ownerAffiliations: [OWNER, COLLABORATOR, ORGANIZATION_MEMBER]) {
      nodes {
        nameWithOwner url pushedAt
        defaultBranchRef { target { ... on Commit { statusCheckRollup { state } } } }
      }
    }
  }
  reviews: search(query: "is:open is:pr review-requested:@me archived:false", type: ISSUE, first: 20) {
    nodes {
      ... on PullRequest { title url number repository { nameWithOwner } author { login } }
    }
  }
}'

notifications=$(gh api notifications -X GET -f per_page=30)
graphql=$(gh api graphql -f query="$query")
printf '{"notifications":%s,"graphql":%s}\n' "$notifications" "$graphql"
