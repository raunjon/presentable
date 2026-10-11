# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`presentable` is a shared Ruby gem (its own git repo, default branch `master`, nested inside the `microservices/` checkout) holding the controller concerns shared by the Rails services that consume it: the JSON response envelope, `?fields=`/`?includes=` filtering, Pagy pagination, error envelopes, gateway-JWT authentication and standard `rescue_from` handlers. The module table and consumer usage are in `README.md`. Code-review guidance is in `AGENTS.md`.

An unrelated `presentable` gem exists on RubyGems, so consumers must always use the `git:` source.

The code was **extracted verbatim from the operator service** (`rwlabs-operator`). Extraction commits deliberately preserve existing behavior, including known bugs; fixes land as separate, later changes. Don't "fix" behavior silently while moving or refactoring code — pinned behavior is covered by characterization tests, and the known issues are documented in the `Presentable::Controller` module comment and the README.

## Commands

```bash
bundle install
bundle exec rake test                                              # full suite (default rake task)
bundle exec ruby -Itest test/presentable/controller_test.rb    # one file
bundle exec ruby -Itest test/presentable/controller_test.rb -n "/page=0/"   # tests matching a name
```

There is no linter configured in this repo.

## Architecture

- `lib/presentable.rb` requires Rails frameworks, Pagy and JWT, then each module. **Require order matters**: modules `include` each other at load time (`ErrorResponses` → `HttpStatusCode`; `SessionErrors` → `ErrorResponses`; `JwtAuthentication` → `SessionErrors`; `StandardRescues` → `ErrorResponses`). Add new files to this list in dependency order.
- **Presentable pipeline**: `Presentable::Controller#present` → `FieldFilterService` (parses `?fields=`, applies `.select`/`.includes`, uses `IncludeBuilderService` for dot-notation includes) → `ResponseBuilderService` (builds `{ data:, success:, current_page:, total_pages:, total_count: }` plus metadata) → `render`. `Presentable::Controller` includes `Pagy::Backend` itself and overrides `pagy` calling `super`, so the backend must stay below it in the ancestor chain (there's a `LayeredLeadsController` test for the case where a parent already includes `Pagy::Backend`). `page=0` means unpaginated.
- **Errors** all render `{ error: { message:, status: }, success: false }` via `response_with`. Only errors generic to all services belong here; service-specific errors (e.g. auth's OTP/platform errors) stay in the service, built on `response_with`.
- **JwtAuthentication** decodes HS256 tokens from the `X-JWT-Token` header (optionally `session[:jwt_token]` via `allow_jwt_from_session!`) using `ENV["RAILS_JWT_SECRET"]` with no fallback, and rejects tokens whose `expires_at` claim (ISO8601 or epoch) is more than `EXPIRY_LEEWAY` (60s) past (401 expired) or unreadable (401 invalid); a missing `expires_at` is accepted. Services reject revoked/logged-out tokens by overriding the private `jwt_revoked?` hook (default `false`, called last, errors propagate). It does not build users or check roles — each service does that.
- `StandardRescues` only registers the `CanCan::AccessDenied` handler if CanCanCan is loaded before the include.

## Tests

- Tests run against a minimal in-memory Rails app in `test/support/dummy_app.rb` (SQLite `:memory:`, schema defined inline with `Venue`/`Event`/`Lead` stand-ins for the operator service's models). Its config mirrors the operator service's (e.g. `consider_all_requests_local = false` is required for `route_not_found` to render the envelope).
- Concerns are exercised through real requests (`ActionDispatch::IntegrationTest`) against test controllers in `test/support/*_controllers.rb` and routes in `test/support/routes.rb`. When adding a concern, add its controller(s) and routes there; keep the catch-all `*path` route last.
- `Gemfile` pins Rails 7.1.5.1, Pagy 9.3.4, Rack, and JWT to the exact versions the operator service uses; the gemspec has the looser runtime ranges. Keep them in sync with the consuming services.
- Eight tests inherited from the operator service are marked `skip` with their verified cause (listed in the README). They document known bugs and should be un-skipped when the corresponding fix lands, not deleted.

## Consuming the gem

Services reference it by git (`branch: "master"`). For local development, a service can point at this checkout with `bundle config set --local local.presentable <path>`; the gem changes must be committed first, because the service's `Gemfile.lock` records the commit SHA.

## Working conventions

- Jira project for this gem is `GEM`.
- **When a Jira ticket is shared, read and follow `docs/instructions.md` first** (worktree question, branch naming, PR).
