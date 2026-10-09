# frozen_string_literal: true

# Header-only JWT auth (the default).
class JwtHeaderOnlyController < ActionController::Base
  include ThirtyplusApi::JwtAuthentication

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
