# frozen_string_literal: true

require "test_helper"

# Characterization tests: pin the error envelopes ErrorResponseActions rendered
# in operator_service at extraction time.
class ThirtyplusApi::ErrorResponsesTest < ActionDispatch::IntegrationTest
  def app
    Dummy::Application
  end

  def json
    JSON.parse(response.body)
  end

  test "render_validation_errors renders 422 with the joined full messages" do
    get "/errors/validation"

    assert_response 422
    assert_equal({ "error" => { "message" => "Name can't be blank", "status" => 422 }, "success" => false }, json)
  end

  test "record_not_found renders 404 with the given message" do
    get "/errors/not_found"

    assert_response 404
    assert_equal({ "error" => { "message" => "Lead not found", "status" => 404 }, "success" => false }, json)
  end

  test "bad_request renders 400 and echoes the offending value" do
    get "/errors/bad"

    assert_response 400
    assert_equal({ "error" => { "value" => "device_id", "message" => "Device ID not found", "status" => 400 }, "success" => false }, json)
  end

  test "method_not_allowed renders 405 and sets the Allow header" do
    get "/errors/not_allowed"

    assert_response 405
    assert_equal "GET, POST", response.headers["Allow"]
    assert_equal "Method Not Allowed", json["error"]["message"]
  end

  test "unauthorized_error renders 403" do
    get "/errors/unauthorized"

    assert_response 403
    assert_equal "You are not authorized to view or edit this content.", json["error"]["message"]
  end

  test "authentication_error renders 403" do
    # NOTE: 403 (not 401) is the extraction-time behavior; preserved as-is.
    get "/errors/authentication"

    assert_response 403
    assert_equal "You must login to continue.", json["error"]["message"]
  end

  test "route_not_found renders 404 for an unknown path" do
    get "/nope"

    assert_response 404
    assert_equal "Path '/nope' not found", json["error"]["message"]
  end

  test "route_not_found renders 405 with Allow when the path exists for another verb" do
    post "/leads"

    assert_response 405
    # Rails routes every GET route for HEAD too, so HEAD is listed.
    assert_equal "GET, HEAD", response.headers["Allow"]
  end
end
