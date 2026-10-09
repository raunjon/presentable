---
name: working-on-gem-ticket
description: Use when the user shares a Jira ticket (GEM-xxx key or thirtyplus.atlassian.net link) to be worked on in the thirtyplus_api gem. Covers the worktree question, branch naming, and raising the PR.
---

# Working on a GEM ticket

The workflow lives in `docs/instructions.md` at the repo root. **Read it and follow it step by step.** Don't work from memory, because the file is the source of truth.

How it fits with Jira:

- **Step 1 (ask where to work) comes before anything else**, including fetching the ticket.
- **Before naming the branch**, read the ticket with `getJiraIssue` (cloudId `thirtyplus.atlassian.net`). Its type and summary decide the prefix and the kebab summary.
- **Once the branch exists and work starts**, transition the ticket to **In Progress**.
- **After the PR is raised**, transition the ticket to **Testing** and add a comment with the PR link. Don't move it to Done; that happens when it's merged and deployed.
- The transition ids in the `tracking-thirtyplus-jira` skill (In Progress 31, Testing 41) are for the `OS` project. Look up `GEM`'s own ids with `getTransitionsForJiraIssue` instead of assuming they match.
