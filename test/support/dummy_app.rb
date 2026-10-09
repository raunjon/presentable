# frozen_string_literal: true

# Minimal Rails app so the gem's controller concerns can be exercised through
# real requests (routing, params, render, respond_to) without a host service.
require "rails"
require "action_controller/railtie"

module Dummy
  class Application < Rails::Application
    # Match operator_service's framework defaults (config/application.rb).
    config.load_defaults 7.0
    # operator_service's ApplicationController skips verify_authenticity_token.
    config.action_controller.default_protect_from_forgery = false
    config.root = File.expand_path("..", __dir__)
    config.eager_load = false
    config.logger = Logger.new(nil)
    config.secret_key_base = "thirtyplus_api_test"
    config.hosts.clear
    config.active_support.deprecation = :silence
    # route_not_found's 404 branch renders the JSON envelope only when this
    # is false (otherwise it cascades with X-Cascade: pass).
    config.consider_all_requests_local = false
    # Let exceptions raise in tests instead of becoming opaque 500 responses.
    config.action_dispatch.show_exceptions = :none
  end
end

Dummy::Application.initialize!

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Migration.verbose = false
ActiveRecord::Schema.define do
  create_table :venues do |t|
    t.string :name
    t.string :access_code
    t.text :internal_notes
  end

  create_table :events do |t|
    t.string :title
    t.date :date
    t.references :venue
  end

  create_table :leads do |t|
    t.string :name
    t.string :email
    t.references :event
  end
end

# Stand-ins for the operator_service models the moved tests were written
# against (Lead belongs to an Event, which belongs to a Venue).
class Venue < ActiveRecord::Base
  include ThirtyplusApi::HiddenAttributes

  has_many :events

  # Hidden from ?fields= (GEM-4): access_code automatically because it is
  # encrypted, internal_notes by declaration.
  encrypts :access_code
  hide_from_api :internal_notes
end

class Event < ActiveRecord::Base
  belongs_to :venue, optional: true
  has_many :leads
end

class Lead < ActiveRecord::Base
  belongs_to :event, optional: true
end
