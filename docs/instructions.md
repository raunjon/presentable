# Jira ticket workflow

Follow these steps every time a Jira ticket (`GEM-xxx`) is shared.

1. **Ask where to work before doing anything else.** Ask whether the work should happen in the current working tree or in a separate, session-based worktree checked out for this ticket. Wait for the answer.
2. **Create a branch** off an up-to-date `master`. Pick the prefix from the kind of work:
   - `feature/`: new behaviour
   - `fix/`: bug fixes
   - `chore/`: tooling, deps, config, docs
   - `refactor/`: restructuring with no behaviour change
   - `test/`: test-only changes

   Format: `<prefix>/GEM-<number>-<short-kebab-summary>`, e.g. `fix/GEM-42-fields-filter-unknown-column`.
3. **Do the work** following `CLAUDE.md`. Run `bundle exec rake test` before finishing (there is no linter in this repo).
4. **Raise a PR** against `master` (remote `origin`, `raunjon/thirtyplus-api`). Fill in `.github/pull_request_template.md`, put the ticket key in the PR title, and link the ticket in the description.
