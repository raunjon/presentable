# frozen_string_literal: true

module ThirtyplusApi
  # Columns a client must never get through ?fields=. Requesting one gets the
  # same 400 as an unknown field (so the response doesn't reveal it exists).
  #
  # Columns declared with +encrypts+ are hidden automatically, whether or not
  # the model includes this concern. Include it to hide other columns:
  #
  #   class Venue < ApplicationRecord
  #     include ThirtyplusApi::HiddenAttributes
  #     hide_from_api :internal_notes
  #   end
  #
  # This only governs ?fields=. A model's own default JSON (no ?fields=) is
  # still whatever its as_json returns.
  module HiddenAttributes
    extend ActiveSupport::Concern

    included do
      class_attribute :api_hidden_attributes, instance_writer: false, default: []
    end

    class_methods do
      def hide_from_api(*names)
        self.api_hidden_attributes = (api_hidden_attributes + names.map(&:to_s)).uniq
      end
    end

    # Column names of +model+ that ?fields= must never expose: declared with
    # hide_from_api, plus every encrypted attribute.
    def self.hidden_columns_for(model)
      declared = model.respond_to?(:api_hidden_attributes) ? model.api_hidden_attributes : []
      encrypted = model.respond_to?(:encrypted_attributes) ? Array(model.encrypted_attributes).map(&:to_s) : []
      declared | encrypted
    end
  end
end
