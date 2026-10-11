# AGENTS.md: code review guide

This file tells code-review agents what to look for in `presentable`, the gem formerly called `thirtyplus_api`. Read `CLAUDE.md` first for what the gem holds and how its modules load. Read `README.md` for the module table and the documented behaviour. The services that consume the gem have their own guides: `../../thirtyplus_operator_service/AGENTS.md`, `../../thirtyplus_auth_service/AGENTS.md` and `../../thirtyplus_gateway/AGENTS.md`.

Every ThirtyPlus Rails service includes this gem in its API base controller, so one bug here ships to all of them at once. The gem turns client-controlled query parameters (`?fields=`, `?includes=`, `?page=`, `?per_page=`) into SQL and serialization calls. It also decides whether a request is authenticated. Focus on security, contract stability and preserved behaviour, not style. The repo is public, so anything committed is published.

## Review priorities, most important first

### 1. Client parameters never reach SQL or method calls unchecked

- **`?fields=` names must be real, visible columns before they reach `.select`**, because `.select` takes raw SQL. `FieldFilterService#validate_fields!` checks every name against `column_names`, and every dot-notation step against `reflect_on_association`. Unknown names get a 400 before any query runs (the README shows `?fields=pg_sleep(5)` as the example). Flag any change that skips that check, reorders `call` so that `apply_field_selection` or `apply_eager_loading` runs first, or adds a path from a param to `.select`.
- **`?includes=` names must be real associations before they reach `.includes` or `as_json(include:)`.** `as_json(include:)` calls the name as a method on the record, so an unchecked `?includes=destroy` deletes it. `validate_includes!` guards against this. Flag any new route from a client string to `send`, `public_send`, `as_json(include:)`, `serializable_hash(include:)`, `.includes`, `.order`, `.where` with a string, or `.pluck`.
- **Polymorphic associations stay rejected.** Their target class can't be checked.
- **New query parameters** (sorting, filtering, search) need the same allow-list treatment and a test with a hostile value.
- **Hostile input gives a 400 envelope, never a 500.** Some 500s are already known (section "What not to flag"). Flag a change that adds a new one.

### 2. Hidden columns stay hidden

- **`Presentable::HiddenAttributes`** hides `hide_from_api` columns and every `encrypts` column, including columns hidden on STI subclasses (via `descendants`). A hidden column gets the same 400 as an unknown one, so the response doesn't reveal that the column exists. Flag any change that gives hidden columns their own message or status, stops hiding encrypted columns automatically, or drops the STI subclass lookup.
- **Known limit:** hiding is enforced only for `?fields=`. Default output and records nested by `?includes=` (`serializable_hash`) are each model's job. Don't re-report the limit itself. Do flag a change that makes it worse, for example by adding a new serialization path that skips the check.

### 3. JWT authentication fails closed

- **The algorithm stays pinned to HS256** in `JWT.decode(..., true, algorithm: ALGORITHM)`. Flag a change that verifies with `false`, accepts `none` or a list of algorithms, or reads the algorithm from the token header.
- **`RAILS_JWT_SECRET` has no fallback.** Flag a default secret, a hard-coded secret, or logging of the secret or the token.
- **The 401 responses are a contract:** `guest_authentication_error` for a missing token, `invalid_token_error` for one that won't decode or has an unreadable `expires_at`, and `token_expired_error` for one that has expired (past `EXPIRY_LEEWAY`) or is revoked. Flag a status or message change, a widened rescue in `decode_jwt` (it must rescue only `JWT::DecodeError`), and anything that rescues errors raised by `jwt_revoked?`. That hook must propagate errors, not fail open.
- **`jwt_claims` is not verification.** It returns the claims of an expired token. Flag gem code, or documentation examples, that grant access from `jwt_claims` without `verify_jwt!`.
- **Scope.** The gem authenticates the token. Building users, checking roles and tenant rules belong to each service. Flag role or tenant logic added here.

### 4. The response and error envelopes are a contract

The gateway, the iOS app and every service depend on these shapes:
- **Success:** `{ data:, success: true }`, plus `current_page`, `total_pages` and `total_count` when paginated.
- **Error:** `{ error: { message:, status: }, success: false }` via `response_with`. A 400 from `bad_request` also has `value`.

Flag renamed or removed keys, changed status codes, or a changed pagination default (10), cap (`max_per_page`, 100) or `page=0` meaning (unpaginated and uncapped). A deliberate change must bump `lib/presentable/version.rb`, update the README, and say in the PR that it is breaking.

### 5. Behaviour is preserved unless the change is the fix

- **Extraction and refactor PRs** (renames, moves, splits) must not change behaviour, including the known bugs. Characterization tests pin the current behaviour. A refactor that edits an assertion is a finding unless the PR explains it.
- **A fix lands with its paperwork:** un-skip the matching `skip "Known failure..."` test rather than deleting it, and remove the bug from the "Behavior to know about" list in `lib/presentable/controller.rb` and from the README.
- **Skipped tests are never deleted to make the suite pass.**

### 6. Load order and the ancestor chain

- **New files go into `lib/presentable.rb` in dependency order.** Modules `include` each other when they load (`ErrorResponses` → `HttpStatusCode`, `SessionErrors` → `ErrorResponses`, `JwtAuthentication` → `SessionErrors`, `StandardRescues` → `ErrorResponses`).
- **`Pagy::Backend` must stay below `Presentable::Controller`** in the ancestor chain, because `Controller#pagy` calls `super`. Flag a change that removes `include Pagy::Backend` from the concern, or that breaks the `LayeredLeadsController` case.
- **`StandardRescues` checks `defined?(CanCan::AccessDenied)` when it is included.** Don't move that check later or make it lazy without a test.

### 7. Only code generic to every service belongs here

- **No service-specific code.** Service-specific errors (auth's OTP and platform errors, for example), model names, tenant logic and role names stay in the services, built on `response_with`. Flag gem code that names a service's models or columns, other than the `Venue`/`Event`/`Lead` stand-ins in `test/support/`.
- **Dependencies:** the `Gemfile` pins Rails 7.1.5.1, Pagy 9.3.4, Rack and JWT to the versions the consuming services use, and the gemspec keeps looser ranges. Flag a new runtime dependency, a range that excludes a version a service runs, or a `Gemfile` pin that drifts from the services.

### 8. Public repo hygiene

Flag committed secrets, real tokens, production hostnames or credentials, customer or user data in fixtures, and internal URLs beyond the Jira references already in `CLAUDE.md` and `docs/`. Test secrets such as `"test-secret"` are fine.

### 9. Tests

Every behaviour change needs a test that fails without the change. Look for:
- **Real requests.** Concerns are tested through `ActionDispatch::IntegrationTest` against the dummy app (`test/support/dummy_app.rb`). A new concern needs its controllers in `test/support/*_controllers.rb` and its routes in `test/support/routes.rb`, with the catch-all `*path` route kept last.
- **Exact assertions.** Assert the status code and the full envelope (`error.message`, `error.value`, `success`), not just `assert_response :bad_request`.
- **Security regression tests** that send the attack itself: an injected `?fields=` value, `?includes=destroy`, a hidden or encrypted column, a token signed with another secret or algorithm, an expired or revoked token. Also assert that nothing happened: no query ran, or the record still exists.
- **A clean suite.** `bundle exec rake test` passes, and the number of skips stays the same unless the PR un-skips a test it fixes.

## What not to flag

- **The bugs listed under "Behavior to know about" in `lib/presentable/controller.rb`**, the skipped `Known failure` tests, and the gaps listed in the README. They are tracked, and fixes land as separate tickets. Flag them only if a PR makes one worse.
- **Code carried over unchanged from operator_service.** Odd style, commented-out lines and long methods are preserved on purpose; report style only if it hides a bug.
- **Lint and style.** There is no linter in this repo.
- **The `Presentable::Controller` name** and the old `thirtyplus_api` checkout directory name. The rename in GEM-1 settled both.
- **Permission, role or tenant rules** that a consuming service should enforce.

## How to report

- **Order findings Critical, then Important, then Minor**, each with `file:line`, what is wrong, a concrete failure scenario (request or input, then the wrong outcome), and the fix.
  - Critical: client input reaching SQL or a method call, a hidden or secret column leaking, a JWT accepted that should be refused, or a secret committed to the public repo.
  - Important: a breaking envelope or status change without a version bump, a silent behaviour change in a refactor, a deleted skipped test, a missing regression test for a security path, or a load-order break.
  - Minor: everything else.
- **Say how you verified it:** read the code, ran a test, or sent a probe request through the dummy app.
- **Separate implementation bugs from design questions** that need a human decision.
