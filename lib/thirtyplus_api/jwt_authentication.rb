# frozen_string_literal: true

module ThirtyplusApi
  # Authenticates requests with the JWT the ThirtyPlus gateway issues and
  # forwards in the X-JWT-Token header, and exposes its claims.
  #
  #   class Api::BaseController < ApplicationController
  #     include ThirtyplusApi::JwtAuthentication
  #     allow_jwt_from_session!          # optional: also read session[:jwt_token]
  #     before_action :verify_jwt!
  #
  #     def current_user
  #       @current_user ||= User.new(id: jwt_claim(:user_id), role: jwt_claim(:role_name))
  #     end
  #   end
  #
  # verify_jwt! renders 401 guest_authentication_error when no token is sent
  # and 401 invalid_token_error when the token can't be decoded or verified
  # (bad signature, malformed, wrong algorithm). Building the user and checking
  # roles stay in each service.
  #
  # It also enforces the gateway's expires_at claim (an ISO8601 time string,
  # or epoch seconds): once it is more than EXPIRY_LEEWAY in the past the
  # token gets 401 token_expired_error, and an expires_at that can't be read
  # gets 401 invalid_token_error. A token without expires_at (or with null) is
  # accepted, since the gateway always sets one. This only enforces the
  # lifetime the token was issued with; it can't see a logout, which happens
  # in the auth service. jwt_claims still returns the claims of an expired
  # token, so check access through verify_jwt!.
  #
  # Tokens are HS256-signed with ENV["RAILS_JWT_SECRET"], which must be set:
  # there is no fallback secret.
  module JwtAuthentication
    extend ActiveSupport::Concern
    include SessionErrors

    ALGORITHM = "HS256"

    # Grace period for clock skew between the gateway and this service.
    EXPIRY_LEEWAY = 60.seconds

    included do
      class_attribute :jwt_session_fallback, instance_writer: false, default: false
    end

    class_methods do
      # Also accept a token stored in session[:jwt_token] when the header is
      # absent (browser logins that keep the token server-side).
      def allow_jwt_from_session!
        self.jwt_session_fallback = true
      end
    end

    def verify_jwt!
      return guest_authentication_error if jwt_token.blank?

      return invalid_token_error if jwt_claims.nil?
      return if jwt_claim(:expires_at).nil?

      expires_at = parse_jwt_expiry(jwt_claim(:expires_at))
      return invalid_token_error if expires_at.nil?

      token_expired_error if Time.current > expires_at + EXPIRY_LEEWAY
    end

    # The raw token: the X-JWT-Token header, else session[:jwt_token] when
    # allow_jwt_from_session! is on.
    def jwt_token
      header_token = request.headers["X-JWT-Token"].presence
      return header_token if header_token
      return session[:jwt_token].presence if jwt_session_fallback

      nil
    end

    # Decoded claims (a Hash with string keys), or nil when there is no token
    # or it doesn't verify.
    def jwt_claims
      return @jwt_claims if defined?(@jwt_claims)

      @jwt_claims = decode_jwt(jwt_token)
    end

    def jwt_claim(name)
      jwt_claims&.[](name.to_s)
    end

    private

    def decode_jwt(token)
      return nil if token.blank?

      JWT.decode(token, jwt_secret, true, algorithm: ALGORITHM).first
    rescue JWT::DecodeError
      nil
    end

    # A Time, or nil when the value isn't an ISO8601 string or a number.
    def parse_jwt_expiry(value)
      case value
      when String then Time.iso8601(value)
      when Numeric then Time.at(value)
      end
    rescue ArgumentError, RangeError
      nil
    end

    def jwt_secret
      ENV["RAILS_JWT_SECRET"].presence || raise("RAILS_JWT_SECRET environment variable is not set")
    end
  end
end
