# frozen_string_literal: true

require "test_helper"

class Presentable::SessionErrorsTest < ActionDispatch::IntegrationTest
  def app
    Dummy::Application
  end

  def json
    JSON.parse(response.body)
  end

  test "guest_authentication_error renders 401" do
    get "/errors/guest"

    assert_response 401
    assert_equal({ "error" => { "message" => "User or Guest User not found", "status" => 401 }, "success" => false }, json)
  end

  test "token_expired_error renders 401" do
    get "/errors/expired"

    assert_response 401
    assert_equal "Session expired, please login again", json["error"]["message"]
  end

  test "guest_token_expired_error renders 401" do
    get "/errors/guest_expired"

    assert_response 401
    assert_equal "Guest session expired, please login again", json["error"]["message"]
  end

  test "invalid_token_error renders 401" do
    get "/errors/invalid_token"

    assert_response 401
    assert_equal({ "error" => { "message" => "Invalid session, please login again", "status" => 401 }, "success" => false }, json)
  end
end
