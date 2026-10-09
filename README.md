# thirtyplus_api

Shared API response envelope, `?fields=`/`?includes=` filtering, Pagy
pagination, and error-envelope helpers for the ThirtyPlus Rails services.

Extracted verbatim from `thirtyplus_operator_service` (2026-10-09). Behavior
is intentionally unchanged from that service; known issues are fixed in later
releases, not during the extraction.

## Contents

| Module | Purpose |
|---|---|
| `ThirtyplusApi::Presentable` | Controller concern: `present`, `set_pagy_and_present`, `present_object_with_metadata`, `?page=0` = unpaginated |
| `ThirtyplusApi::FieldFilterService` | Parses `?fields=`, applies `.select` / `.includes` |
| `ThirtyplusApi::IncludeBuilderService` | Dot-notation includes → `.includes` and `as_json` structures |
| `ThirtyplusApi::ResponseBuilderService` | Builds the `{ data:, success:, current_page:, total_pages:, total_count: }` envelope |
| `ThirtyplusApi::ErrorResponses` | `{ error: { message:, status: }, success: false }` helpers (`render_validation_errors`, `record_not_found`, `route_not_found`, ...) |
| `ThirtyplusApi::SessionErrors` | `guest_authentication_error`, `invalid_token_error`, `token_expired_error`, `guest_token_expired_error` (includes `ErrorResponses`) |
| `ThirtyplusApi::JwtAuthentication` | Gateway JWT auth: `verify_jwt!` (401 when missing or invalid), `jwt_claims`, `jwt_claim(:user_id)`, opt-in `allow_jwt_from_session!`. HS256 with `RAILS_JWT_SECRET`, no fallback. Includes `SessionErrors` |
| `ThirtyplusApi::StandardRescues` | `rescue_from` `ActiveRecord::RecordNotFound` → 404 and, when CanCanCan is loaded, `CanCan::AccessDenied` → 403 |
| `ThirtyplusApi::HttpStatusCode` | `*_status_code` helpers |

Service-specific errors (auth's OTP/platform errors, etc.) stay in each
service, built on `response_with`.

## Usage

```ruby
# Gemfile
gem "thirtyplus_api", git: "https://github.com/raunjon/thirtyplus-api.git", branch: "master"

# controllers
class Api::BaseController < ApplicationController
  include ThirtyplusApi::JwtAuthentication   # also brings in SessionErrors + ErrorResponses
  include ThirtyplusApi::StandardRescues     # RecordNotFound -> 404, CanCan::AccessDenied -> 403
  before_action :verify_jwt!

  def current_user                           # each service builds its own user
    @current_user ||= User.new(id: jwt_claim(:user_id), role: jwt_claim(:role_name))
  end
end

class Api::V1::BaseController < Api::BaseController
  include ThirtyplusApi::Presentable     # also brings in Pagy::Backend
end
```

## Local development

Point a service at your checkout instead of GitHub (per service, not committed):

```bash
bundle config set --local local.thirtyplus_api /absolute/path/to/microservices/gems/thirtyplus_api
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
SQLite). Eight tests carried over from operator_service were already failing
there; they are kept and marked `skip` with the verified cause, to be fixed in
follow-up releases:

- `FieldFilterServiceTest`: `parses includes parameter`, `includes foreign keys when associations are present`, `applies eager loading with includes` (`params[:includes]` is ignored), `handles deeply nested association fields` (splits on first `.` only)
- `IncludeBuilderServiceTest`: `handles multiple nested associations for same parent`, `handles duplicate associations`
- `ResponseBuilderServiceTest`: `includes pagination without count`, `handles nil metadata` (test bugs)
