#!/bin/sh
# Prints the GraphQL data the GitHub Counts widget needs, using the gh CLI's stored login.
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
