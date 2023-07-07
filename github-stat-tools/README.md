# Github stats tools

## github-pending.py

This script connects with the given github repository, finds out the amount
of open PRs and issues, and feeds the amount to a chosen backend.  The
backend will determine where that metric ends up.

## parse-commitlog-to-find-companies.py

Given a git log create data for a sankey graph of where our commits come
from, so we can find out how many commits are from paid resources,
committers, people under a CCLA, and so on.
