# frozen_string_literal: true

# Header-only JWT auth (the default).
class JwtHeaderOnlyController < ActionController::Base
  include Presentable::JwtAuthentication

  before_action :verify_jwt!, only: :claims

  def claims
    render json: { user_id: jwt_claim(:user_id), role_name: jwt_claim("role_name") }
  end

  # Stores a token in the session, the way operator_service's
  # SessionsController#set_jwt does.
  def login
    session[:jwt_token] = params[:token]
    head :ok
  end
end

# Same, but also accepts session[:jwt_token].
class JwtWithSessionController < JwtHeaderOnlyController
  allow_jwt_from_session!
end

# Overrides the jwt_revoked? hook: a token whose "token" claim is "revoked"
# is revoked, and "boom" makes the lookup fail. Every call is flagged in a
# response header so tests can tell whether the hook ran.
class JwtRevocationController < JwtHeaderOnlyController
  private

  def jwt_revoked?
    response.headers["X-Revocation-Checked"] = "true"
    raise "revocation lookup failed" if jwt_claim(:token) == "boom"

    jwt_claim(:token) == "revoked"
  end
end
