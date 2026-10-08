# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "thirtyplus_api"
require_relative "support/dummy_app"
Dir[File.join(__dir__, "support", "*.rb")].sort.each { |file| require file }

require "minitest/autorun"
require "active_support/test_case"
require "action_dispatch/testing/integration"
