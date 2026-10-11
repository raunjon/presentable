# frozen_string_literal: true

require "test_helper"

class Presentable::StandardRescuesTest < ActionDispatch::IntegrationTest
  def app
    Dummy::Application
  end

  def json
    JSON.parse(response.body)
  end

  test "ActiveRecord::RecordNotFound renders 404 with the exception message" do
    get "/rescues/not_found"

    assert_response 404
    assert_equal({ "error" => { "message" => "Couldn't find Lead with 'id'=-1", "status" => 404 }, "success" => false }, json)
  end

  test "CanCan::AccessDenied renders 403 unauthorized_error" do
    get "/rescues/access_denied"

    assert_response 403
    assert_equal "You are not authorized to view or edit this content.", json["error"]["message"]
  end

  test "other exceptions are not rescued" do
    assert_raises(ArgumentError) { get "/rescues/unhandled" }
  end
end
