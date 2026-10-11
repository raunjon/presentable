# frozen_string_literal: true

require "test_helper"

class Presentable::JwtAuthenticationTest < ActionDispatch::IntegrationTest
  SECRET = "test-secret"

  def app
    Dummy::Application
  end

  setup do
    @previous_secret = ENV["RAILS_JWT_SECRET"]
    ENV["RAILS_JWT_SECRET"] = SECRET
  end

  teardown do
    ENV["RAILS_JWT_SECRET"] = @previous_secret
  end

  def token(claims = { "user_id" => 7, "role_name" => "admin" }, secret: SECRET, algorithm: "HS256")
    JWT.encode(claims, secret, algorithm)
  end

  def json
    JSON.parse(response.body)
  end

  test "a valid header token passes and exposes its claims" do
    get "/jwt/claims", headers: { "X-JWT-Token" => token }

    assert_response :ok
    assert_equal({ "user_id" => 7, "role_name" => "admin" }, json)
  end

  test "a missing token renders 401 guest_authentication_error" do
    get "/jwt/claims"

    assert_response 401
    assert_equal "User or Guest User not found", json["error"]["message"]
  end

  test "an empty header counts as missing" do
    get "/jwt/claims", headers: { "X-JWT-Token" => "" }

    assert_response 401
    assert_equal "User or Guest User not found", json["error"]["message"]
  end

  test "a malformed token renders 401 invalid_token_error" do
    get "/jwt/claims", headers: { "X-JWT-Token" => "not.a.jwt" }

    assert_response 401
    assert_equal "Invalid session, please login again", json["error"]["message"]
  end

  test "a token signed with another secret renders 401 invalid_token_error" do
    get "/jwt/claims", headers: { "X-JWT-Token" => token(secret: "someone-else") }

    assert_response 401
    assert_equal "Invalid session, please login again", json["error"]["message"]
  end

  test "a token signed with another algorithm renders 401 invalid_token_error" do
    get "/jwt/claims", headers: { "X-JWT-Token" => token(algorithm: "HS512") }

    assert_response 401
    assert_equal "Invalid session, please login again", json["error"]["message"]
  end

  test "a missing RAILS_JWT_SECRET raises instead of using a fallback" do
    ENV["RAILS_JWT_SECRET"] = nil

    error = assert_raises(RuntimeError) do
      get "/jwt/claims", headers: { "X-JWT-Token" => token }
    end
    assert_equal "RAILS_JWT_SECRET environment variable is not set", error.message
  end

  test "a session token is ignored unless the controller opts in" do
    post "/jwt/login", params: { token: token }
    get "/jwt/claims"

    assert_response 401
    assert_equal "User or Guest User not found", json["error"]["message"]
  end

  test "allow_jwt_from_session! accepts a session token" do
    post "/jwt_session/login", params: { token: token }
    get "/jwt_session/claims"

    assert_response :ok
    assert_equal 7, json["user_id"]
  end

  test "the header wins over the session token" do
    post "/jwt_session/login", params: { token: token({ "user_id" => 1, "role_name" => "user" }) }
    get "/jwt_session/claims", headers: { "X-JWT-Token" => token({ "user_id" => 2, "role_name" => "admin" }) }

    assert_equal 2, json["user_id"]
  end

  def token_expiring(expires_at)
    token({ "user_id" => 7, "role_name" => "admin", "expires_at" => expires_at })
  end

  def assert_session_expired
    assert_response 401
    assert_equal "Session expired, please login again", json["error"]["message"]
  end

  def assert_invalid_session
    assert_response 401
    assert_equal "Invalid session, please login again", json["error"]["message"]
  end

  test "a future expires_at (ISO8601, as the gateway sends it) passes" do
    get "/jwt/claims", headers: { "X-JWT-Token" => token_expiring(1.day.from_now.utc.iso8601(3)) }

    assert_response :ok
    assert_equal 7, json["user_id"]
  end

  test "a future expires_at with a UTC offset passes" do
    get "/jwt/claims", headers: { "X-JWT-Token" => token_expiring(1.day.from_now.getlocal("+05:30").iso8601) }

    assert_response :ok
  end

  test "a future expires_at as epoch seconds passes" do
    get "/jwt/claims", headers: { "X-JWT-Token" => token_expiring(1.day.from_now.to_i) }

    assert_response :ok
  end

  test "a past expires_at renders 401 token_expired_error" do
    get "/jwt/claims", headers: { "X-JWT-Token" => token_expiring(1.day.ago.utc.iso8601) }

    assert_session_expired
  end

  test "a past expires_at as epoch seconds renders 401 token_expired_error" do
    get "/jwt/claims", headers: { "X-JWT-Token" => token_expiring(1.day.ago.to_i) }

    assert_session_expired
  end

  test "an expires_at within the clock leeway still passes" do
    get "/jwt/claims", headers: { "X-JWT-Token" => token_expiring(30.seconds.ago.utc.iso8601) }

    assert_response :ok
  end

  test "an expires_at just past the clock leeway renders 401 token_expired_error" do
    get "/jwt/claims", headers: { "X-JWT-Token" => token_expiring(90.seconds.ago.utc.iso8601) }

    assert_session_expired
  end

  test "a token without expires_at passes" do
    get "/jwt/claims", headers: { "X-JWT-Token" => token }

    assert_response :ok
  end

  test "a null expires_at counts as missing and passes" do
    get "/jwt/claims", headers: { "X-JWT-Token" => token_expiring(nil) }

    assert_response :ok
  end

  test "an unparseable expires_at renders 401 invalid_token_error" do
    get "/jwt/claims", headers: { "X-JWT-Token" => token_expiring("tomorrow") }

    assert_invalid_session
  end

  test "an empty expires_at renders 401 invalid_token_error" do
    get "/jwt/claims", headers: { "X-JWT-Token" => token_expiring("") }

    assert_invalid_session
  end

  test "a non-ISO8601 date string renders 401 invalid_token_error" do
    get "/jwt/claims", headers: { "X-JWT-Token" => token_expiring("10/09/2099") }

    assert_invalid_session
  end

  test "an expires_at of the wrong type renders 401 invalid_token_error" do
    get "/jwt/claims", headers: { "X-JWT-Token" => token_expiring({ "at" => "2099-01-01" }) }

    assert_invalid_session
  end

  test "an expired session token renders 401 token_expired_error" do
    post "/jwt_session/login", params: { token: token_expiring(1.day.ago.utc.iso8601) }
    get "/jwt_session/claims"

    assert_session_expired
  end

  def revocable_token(token_claim, expires_at: 1.day.from_now.utc.iso8601)
    token({ "user_id" => 7, "role_name" => "admin", "token" => token_claim, "expires_at" => expires_at })
  end

  def revocation_checked?
    response.headers["X-Revocation-Checked"] == "true"
  end

  test "without an override jwt_revoked? is false and valid tokens pass" do
    get "/jwt/claims", headers: { "X-JWT-Token" => revocable_token("revoked") }

    assert_response :ok
  end

  test "a token the service reports as revoked renders 401 token_expired_error" do
    get "/jwt_revocation/claims", headers: { "X-JWT-Token" => revocable_token("revoked") }

    assert revocation_checked?
    assert_session_expired
  end

  test "a token the service doesn't report as revoked passes" do
    get "/jwt_revocation/claims", headers: { "X-JWT-Token" => revocable_token("live") }

    assert revocation_checked?
    assert_response :ok
    assert_equal 7, json["user_id"]
  end

  test "a revoked token without expires_at still renders 401 token_expired_error" do
    get "/jwt_revocation/claims", headers: { "X-JWT-Token" => revocable_token("revoked", expires_at: nil) }

    assert revocation_checked?
    assert_session_expired
  end

  test "an error in jwt_revoked? propagates instead of failing open" do
    error = assert_raises(RuntimeError) do
      get "/jwt_revocation/claims", headers: { "X-JWT-Token" => revocable_token("boom") }
    end
    assert_equal "revocation lookup failed", error.message
  end

  test "jwt_revoked? is not called for a missing token" do
    get "/jwt_revocation/claims"

    refute revocation_checked?
    assert_response 401
  end

  test "jwt_revoked? is not called for an invalid token" do
    get "/jwt_revocation/claims", headers: { "X-JWT-Token" => "not.a.jwt" }

    refute revocation_checked?
    assert_invalid_session
  end

  test "jwt_revoked? is not called for an unreadable expires_at" do
    get "/jwt_revocation/claims", headers: { "X-JWT-Token" => revocable_token("live", expires_at: "tomorrow") }

    refute revocation_checked?
    assert_invalid_session
  end

  test "jwt_revoked? is not called for an expired token" do
    get "/jwt_revocation/claims", headers: { "X-JWT-Token" => revocable_token("live", expires_at: 1.day.ago.utc.iso8601) }

    refute revocation_checked?
    assert_session_expired
  end

  test "allow_jwt_from_session! does not leak to the parent controller" do
    refute JwtHeaderOnlyController.jwt_session_fallback
    assert JwtWithSessionController.jwt_session_fallback
  end
end
