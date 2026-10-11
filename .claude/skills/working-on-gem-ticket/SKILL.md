---
name: working-on-gem-ticket
description: Use when the user shares a Jira ticket (GEM-xxx key or Jira link) to be worked on in the presentable gem. Covers the worktree question, branch naming, and raising the PR.
---

# Working on a GEM ticket

The workflow lives in `docs/instructions.md` at the repo root. **Read it and follow it step by step.** Don't work from memory, because the file is the source of truth.

How it fits with Jira:

- **Step 1 (ask where to work) comes before anything else**, including fetching the ticket.
- **Before naming the branch**, read the ticket with `getJiraIssue` (cloudId `c6a796dc-db97-4a03-ac19-dd59d3104970`). Its type and summary decide the prefix and the kebab summary.
- **Once the branch exists and work starts**, transition the ticket to **In Progress**.
- **After the PR is raised**, transition the ticket to **Testing** and add a comment with the PR link. Don't move it to Done; that happens when it's merged and deployed.
- Transition ids from other Jira projects don't carry over. Look up `GEM`'s own ids with `getTransitionsForJiraIssue` instead of assuming they match.
