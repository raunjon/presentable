# frozen_string_literal: true

require "test_helper"

class ThirtyplusApi::JwtAuthenticationTest < ActionDispatch::IntegrationTest
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

  test "allow_jwt_from_session! does not leak to the parent controller" do
    refute JwtHeaderOnlyController.jwt_session_fallback
    assert JwtWithSessionController.jwt_session_fallback
  end
end
