# frozen_string_literal: true

require "test_helper"

# Characterization tests: pin the behavior Presentable had in operator_service
# at extraction time. Some of it is questionable (see the NOTE comments) and is
# deliberately preserved -- fixes come in later, separate gem changes.
class ThirtyplusApi::PresentableTest < ActionDispatch::IntegrationTest
  def app
    Dummy::Application
  end

  setup do
    @event = Event.create!(title: "Mixer")
    12.times { |i| Lead.create!(name: "Lead #{i}", email: "lead#{i}@example.com", event: @event) }
  end

  teardown do
    Lead.delete_all
    Event.delete_all
  end

  def json
    JSON.parse(response.body)
  end

  test "index paginates 10 per page by default with pagination metadata" do
    get "/leads"

    assert_response :ok
    assert_equal true, json["success"]
    assert_equal 10, json["data"].length
    assert_equal 1, json["current_page"]
    assert_equal 2, json["total_pages"]
    assert_equal 12, json["total_count"]
  end

  test "per_page and page select the requested slice" do
    get "/leads", params: { per_page: 5, page: 2 }

    assert_equal 5, json["data"].length
    assert_equal 2, json["current_page"]
    assert_equal 3, json["total_pages"]
    assert_equal "Lead 5", json["data"].first["name"]
  end

  test "page=0 returns every record without pagination metadata" do
    get "/leads", params: { page: 0 }

    assert_equal 12, json["data"].length
    refute json.key?("current_page")
    refute json.key?("total_pages")
  end

  test "a page past the end returns an empty list" do
    get "/leads", params: { page: 99 }

    assert_response :ok
    assert_equal [], json["data"]
    # NOTE: pagy_object is still nil inside the Pagy::OverflowError rescue, so
    # the pagination keys are dropped even though the code comment promises a
    # "valid pagy". Preserved as-is.
    refute json.key?("current_page")
  end

  test "fields limits each record to the requested columns plus id" do
    get "/leads", params: { fields: "name" }

    assert_equal %w[id name], json["data"].first.keys.sort
  end

  test "includes nests the association in each record" do
    get "/leads", params: { includes: "event" }

    assert_equal "Mixer", json["data"].first["event"]["title"]
  end

  test "fields with dot notation limits the nested association's columns" do
    get "/leads", params: { fields: "name,event.title" }

    record = json["data"].first
    # event_id is SELECTed so the association can load, but as_json(only:)
    # leaves it out of the rendered record.
    assert_equal %w[event id name], record.keys.sort
    assert_equal %w[id title], record["event"].keys.sort
  end

  test "show presents a single record under data" do
    lead = Lead.first
    get "/leads/#{lead.id}"

    assert_equal lead.id, json["data"]["id"]
    assert_equal true, json["success"]
  end

  test "show applies fields to a single record" do
    get "/leads/#{Lead.first.id}", params: { fields: "email" }

    assert_equal %w[email id], json["data"].keys.sort
  end

  test "present_object_with_metadata merges metadata into the envelope" do
    get "/leads/with_metadata"

    assert_equal true, json["filters_applied"]
    assert_equal 12, json["data"].length
  end

  test "works when the host already includes Pagy::Backend in a parent controller" do
    get "/layered_leads", params: { per_page: 5 }
    assert_equal 5, json["data"].length
    assert_equal 3, json["total_pages"]

    get "/layered_leads", params: { page: 0 }
    assert_equal 12, json["data"].length
    refute json.key?("current_page")
  end

  test "unknown fields render 400 and never reach the database" do
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      get "/leads", params: { fields: "id,pg_sleep(5)" }
    end

    assert_response 400
    assert_equal({ "error" => { "value" => "fields", "message" => "Unknown fields: pg_sleep(5)", "status" => 400 }, "success" => false }, json)
    assert queries.none? { |sql| sql.include?("pg_sleep") }, "pg_sleep reached the database: #{queries.inspect}"
  end

  test "an unknown related field renders 400" do
    get "/leads", params: { fields: "name,event.nope" }

    assert_response 400
    assert_equal "Unknown fields: event.nope", json["error"]["message"]
  end

  test "an unknown field on show renders 400" do
    get "/leads/#{Lead.first.id}", params: { fields: "bogus" }

    assert_response 400
    assert_equal "Unknown fields: bogus", json["error"]["message"]
  end

  test "a trailing dot renders 400 instead of an error" do
    get "/leads", params: { fields: "name." }

    assert_response 400
    assert_equal "Unknown fields: name.", json["error"]["message"]
  end

  test "?includes=destroy on show renders 400 and does not delete the record" do
    lead = Lead.first
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      get "/leads/#{lead.id}", params: { includes: "destroy" }
    end

    assert_response 400
    assert_equal({ "error" => { "value" => "includes", "message" => "Unknown includes: destroy", "status" => 400 }, "success" => false }, json)
    assert Lead.exists?(lead.id), "the record was deleted"
    assert queries.none? { |sql| sql =~ /DELETE/i }, "a DELETE ran: #{queries.inspect}"
  end

  test "?includes=destroy on index renders 400 and deletes nothing" do
    get "/leads", params: { includes: "destroy" }

    assert_response 400
    assert_equal 12, Lead.count
  end

  test "an unknown include on index renders 400 instead of an error" do
    get "/leads", params: { includes: "nope" }

    assert_response 400
    assert_equal "Unknown includes: nope", json["error"]["message"]
  end

  test "empty entries in ?includes= are ignored" do
    get "/leads", params: { includes: "event,,", page: 0 }

    assert_response :ok
    assert_equal "Mixer", json["data"].first["event"]["title"]
  end

  test "a valid ?fields= does not let a dangerous ?includes= through" do
    lead = Lead.first

    get "/leads/#{lead.id}", params: { fields: "name,event.title", includes: "destroy" }

    assert_response 400
    assert_equal "Unknown includes: destroy", json["error"]["message"]
    assert Lead.exists?(lead.id)
  end

  test "X-Content-Type containing xml renders XML" do
    get "/leads", params: { page: 0 }, headers: { "X-Content-Type" => "application/xml" }

    assert_includes response.media_type, "xml"
    assert_includes response.body, "<success type=\"boolean\">true</success>"
  end
end
