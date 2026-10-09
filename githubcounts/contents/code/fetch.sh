#!/bin/sh
# Prints the GraphQL data the GitHub Counts widget needs, using the gh CLI's stored login.
# Usage: fetch.sh <account>
# The first argument picks which gh account to use; empty means gh's active account.
# The account's token is passed to gh in the environment, not on the command line.
if [ -n "$1" ]; then
    GH_TOKEN=$(gh auth token --hostname github.com --user "$1" 2>/dev/null) || {
        echo "gh is not logged in as $1. Run: gh auth login" >&2
        exit 4
    }
    export GH_TOKEN
fi

exec gh api graphql -f query='{
  viewer {
    login
    repositories(first: 8, orderBy: {field: PUSHED_AT, direction: DESC},
                 ownerAffiliations: [OWNER, COLLABORATOR, ORGANIZATION_MEMBER]) {
      nodes {
        nameWithOwner url
        defaultBranchRef { target { ... on Commit { statusCheckRollup { state } } } }
      }
    }
  }
  prs: search(query: "is:open is:pr author:@me archived:false", type: ISSUE, first: 50) {
    issueCount
    nodes {
      ... on PullRequest {
        title url
        commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
      }
    }
  }
  reviews: search(query: "is:open is:pr review-requested:@me archived:false", type: ISSUE, first: 1) {
    issueCount
  }
}'
