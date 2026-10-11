# Presentable

Shared API response envelope, `?fields=`/`?includes=` filtering, Pagy
pagination, and error-envelope helpers for Rails API services.

Install it from git, as shown in Usage. An unrelated gem named `presentable`
exists on RubyGems, so a plain `gem "presentable"` would install that gem
instead.

## Contents

| Module | Purpose |
|---|---|
| `Presentable::Controller` | Controller concern: `present`, `set_pagy_and_present`, `present_object_with_metadata`. `?per_page=` capped at `max_per_page` (100); `?page=0` = unpaginated, uncapped |
| `Presentable::FieldFilterService` | Parses `?fields=`, applies `.select` / `.includes` |
| `Presentable::HiddenAttributes` | Model concern: `hide_from_api :col`. Hidden columns (these, plus every `encrypts` column automatically) can't be requested with `?fields=` |
| `Presentable::IncludeBuilderService` | Dot-notation includes → `.includes` and `as_json` structures |
| `Presentable::ResponseBuilderService` | Builds the `{ data:, success:, current_page:, total_pages:, total_count: }` envelope |
| `Presentable::ErrorResponses` | `{ error: { message:, status: }, success: false }` helpers (`render_validation_errors`, `record_not_found`, `route_not_found`, ...) |
| `Presentable::SessionErrors` | `guest_authentication_error`, `invalid_token_error`, `token_expired_error`, `guest_token_expired_error` (includes `ErrorResponses`) |
| `Presentable::JwtAuthentication` | Gateway JWT auth: `verify_jwt!` (401 when missing, invalid, past its `expires_at`, or revoked via the `jwt_revoked?` hook), `jwt_claims`, `jwt_claim(:user_id)`, opt-in `allow_jwt_from_session!`. HS256 with `RAILS_JWT_SECRET`, no fallback. Includes `SessionErrors` |
| `Presentable::StandardRescues` | `rescue_from` `ActiveRecord::RecordNotFound` → 404 and, when CanCanCan is loaded, `CanCan::AccessDenied` → 403 |
| `Presentable::HttpStatusCode` | `*_status_code` helpers |

Service-specific errors (auth's OTP/platform errors, etc.) stay in each
service, built on `response_with`.

## Pagination (`?page=`, `?per_page=`)

`set_pagy_and_present` returns 10 records per page. `?per_page=` changes the
page size up to a maximum of 100. A larger value is reduced to the maximum,
not rejected, and `total_pages` is counted with the reduced size. A blank,
non-integer, zero or negative `per_page` uses the default of 10.

`?page=0` returns every record, unpaginated, and ignores both `per_page` and
the maximum. Use it only on endpoints whose lists are meant to be fetched whole.

A service can change the maximum for a controller and its subclasses:

```ruby
class Api::V1::BaseController < Api::BaseController
  include Presentable::Controller
  self.max_per_page = 50
end
```

## Field selection (`?fields=`)

`?fields=` only accepts real column names. Dot notation must name a real
association followed by a real column on it, e.g. `event.title` or
`event.venue.name`. Any other name gets a 400 before a query runs:

```json
{"error":{"value":"fields","message":"Unknown fields: pg_sleep(5)","status":400},"success":false}
```

Empty entries (`name,,email`) are ignored.

**Hidden columns** get the same 400 as an unknown name, so a client can't tell
they exist. A column is hidden when it is declared with `encrypts`, which needs
no extra code, or when the model lists it explicitly:

```ruby
class Venue < ApplicationRecord
  include Presentable::HiddenAttributes
  hide_from_api :internal_notes
end
```

This only governs `?fields=`. Default output uses the model's `as_json`,
but records nested via `?includes=` are serialized with `serializable_hash`,
which skips `as_json` overrides. To keep a secret column out everywhere,
exclude it in `serializable_hash` (which `as_json` also uses), not only in
`as_json`.

## Related records (`?includes=`)

`?includes=` only accepts real associations, with each step checked for dot
notation (`event`, `event.venue`). Any other name gets a 400 before eager
loading or serialization (no association or method is called), so
`?includes=destroy` can no longer delete a record:

```json
{"error":{"value":"includes","message":"Unknown includes: destroy","status":400},"success":false}
```

Empty entries (`event,,venue`) are ignored. Polymorphic associations are
rejected, because their target can't be checked.

## Usage

```ruby
# Gemfile
gem "presentable", git: "https://github.com/raunjon/presentable.git", branch: "master"

# controllers
class Api::BaseController < ApplicationController
  include Presentable::JwtAuthentication   # also brings in SessionErrors + ErrorResponses
  include Presentable::StandardRescues     # RecordNotFound -> 404, CanCan::AccessDenied -> 403
  before_action :verify_jwt!

  def current_user                           # each service builds its own user
    @current_user ||= User.new(id: jwt_claim(:user_id), role: jwt_claim(:role_name))
  end
end

class Api::V1::BaseController < Api::BaseController
  include Presentable::Controller     # also brings in Pagy::Backend
end
```

### Token expiry

`verify_jwt!` checks the gateway's `expires_at` claim:

| `expires_at` | Result |
|---|---|
| In the future, or less than 60 seconds past (`EXPIRY_LEEWAY`, for clock skew) | passes |
| More than 60 seconds past | 401 `Session expired, please login again` |
| Missing or `null` | passes (the gateway always sets one) |
| Not an ISO8601 string or epoch number (`"tomorrow"`, `""`, `"10/09/2099"`) | 401 `Invalid session, please login again` |

This enforces the lifetime the token was issued with (per role: 1 day for
guests, 1 month for staff, 6 months for users). `jwt_claims` still returns an
expired token's claims, so gate access with `verify_jwt!`.

### Revoked tokens (logout)

A logout doesn't change `expires_at`, so a logged-out token passes until its
original expiry unless the service tells the gem it's revoked. Override the
private `jwt_revoked?` hook and look the token up wherever the service keeps
revocations:

```ruby
class Api::BaseController < ApplicationController
  include Presentable::JwtAuthentication
  before_action :verify_jwt!

  private

  def jwt_revoked?
    RevokedToken.exists?(token: jwt_claim(:token))
  end
end
```

- Default: `false`, so nothing changes until a service overrides it.
- `true` → 401 `Session expired, please login again`.
- Runs only after every other check passes, so already-rejected tokens (missing,
  invalid, expired) never trigger a lookup.
- Errors raised inside it propagate; the gem never fails open.

## Local development

Point a service at your checkout instead of GitHub (per service, not committed):

```bash
bundle config set --local local.presentable /absolute/path/to/your/presentable/checkout
bundle install
```

The checkout must be on branch `master`. Commit gem changes before running
`bundle install` in the service; the service's `Gemfile.lock` records the commit.

## Tests

```bash
bundle install
bundle exec rake test
```

Tests run against a minimal in-memory Rails app (`test/support/dummy_app.rb`,
SQLite). Eight tests carried over from the original code were already failing
there; they are kept and marked `skip` with the verified cause, to be fixed in
follow-up releases:

- `FieldFilterServiceTest`: `parses includes parameter`, `includes foreign keys when associations are present`, `applies eager loading with includes` (`params[:includes]` is ignored), `handles deeply nested association fields` (splits on first `.` only)
- `IncludeBuilderServiceTest`: `handles multiple nested associations for same parent`, `handles duplicate associations`
- `ResponseBuilderServiceTest`: `includes pagination without count`, `handles nil metadata` (test bugs)
