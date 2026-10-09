#!/bin/sh
# Prints {"notifications": [...], "graphql": {...}} for the GitHub Account widget.
# Uses the gh CLI's stored login, so the widget never handles a token itself.
# With "mark-read" as the first argument, marks all notifications read first.
set -e

if [ "$1" = "mark-read" ]; then
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
