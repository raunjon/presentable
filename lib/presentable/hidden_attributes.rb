# frozen_string_literal: true

module Presentable
  # Columns a client must never get through ?fields=. Requesting one gets the
  # same 400 as an unknown field (so the response doesn't reveal it exists).
  #
  # Columns declared with +encrypts+ are hidden automatically, whether or not
  # the model includes this concern. Include it to hide other columns:
  #
  #   class Venue < ApplicationRecord
  #     include Presentable::HiddenAttributes
  #     hide_from_api :internal_notes
  #   end
  #
  # This only governs ?fields=. Default output (no ?fields=) uses the model's
  # as_json. Records nested via ?includes= are serialized with
  # serializable_hash, which skips as_json overrides. To keep a secret column
  # out everywhere, exclude it in serializable_hash (as_json uses it too), not
  # only in as_json.
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

    # Column names that ?fields= must never expose for +model+: declared with
    # hide_from_api, plus every encrypted attribute. Includes columns hidden on
    # any STI subclass, because querying the base class returns subclass
    # instances. Per class: declared first, then encrypted, no duplicates.
    # Note: +descendants+ only sees loaded subclasses, so apps that use STI
    # must eager-load them (production does by default).
    def self.hidden_columns_for(model)
      [model, *model.descendants].flat_map { |klass| own_hidden_columns(klass) }.uniq
    end

    def self.own_hidden_columns(klass)
      declared = klass.respond_to?(:api_hidden_attributes) ? klass.api_hidden_attributes : []
      encrypted = klass.respond_to?(:encrypted_attributes) ? Array(klass.encrypted_attributes).map(&:to_s) : []
      declared | encrypted
    end
    private_class_method :own_hidden_columns
  end
end
