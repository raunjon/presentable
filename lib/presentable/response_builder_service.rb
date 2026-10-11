# frozen_string_literal: true

module Presentable
  # Service for building API response data with field filtering and pagination
  # Handles JSON/XML rendering with proper field selection and metadata
  #
  # This service centralizes the response building logic that was previously
  # scattered across base controllers. It handles:
  # - Field filtering for JSON responses
  # - Pagination metadata
  # - Association field selection
  # - Custom metadata merging
  #
  # @example Basic usage
  #   builder = Presentable::ResponseBuilderService.new(
  #     object: @entries,
  #     pagy: pagy_object,
  #     key: :entries
  #   )
  #   render builder.to_json
  #
  # @example With field filtering
  #   builder = Presentable::ResponseBuilderService.new(
  #     object: @entries,
  #     main_fields: ['id', 'name'],
  #     includes: [:event],
  #     association_fields: { 'event' => ['title'] }
  #   )
  #   render builder.to_json
  #
  class ResponseBuilderService
    # Initialize the response builder
    #
    # @param object [Object] The object/collection to serialize
    # @param key [Symbol] The key to wrap the data in (default: :data)
    # @param pagy [Pagy] Optional pagination object
    # @param status [Integer] HTTP status code (default: 200)
    # @param main_fields [Array<String>] Fields to include from main model
    # @param includes [Array] Associations to include
    # @param association_fields [Hash] Fields to include from associations
    # @param metadata [Hash] Additional metadata to include
    def initialize(object:, key: :data, pagy: nil, status: 200, main_fields: nil, includes: [], association_fields: {}, metadata: {})
      @object = object
      @key = key
      @pagy = pagy
      @status = status
      @main_fields = main_fields
      @includes = includes || []
      @association_fields = association_fields || {}
      @metadata = metadata || {}
    end

    # Build the complete response hash
    #
    # @return [Hash] Response data ready for rendering
    def build
      data = { @key => serialized_object, success: true }

      add_pagination(data) if @pagy
      data.merge!(@metadata) if @metadata.any?

      data
    end

    # Get render options for Rails controller
    #
    # @return [Hash] Options to pass to render method
    #
    # @example
    #   render builder.render_options
    #   # => render json: { data: [...], success: true }, status: 200
    def render_options
      {
        json: build,
        status: @status
      }
    end

    # Build JSON response
    # Alias for render_options for clarity
    #
    # @return [Hash] JSON render options
    def to_json
      render_options
    end

    private

    # Serialize the object with field filtering
    def serialized_object
      return @object unless should_apply_field_filtering?

      if @object.is_a?(ActiveRecord::Base)
        serialize_single_record
      elsif @object.is_a?(ActiveRecord::Relation) || @object.is_a?(Array)
        serialize_collection
      else
        @object
      end
    end

    # Check if field filtering should be applied
    def should_apply_field_filtering?
      @main_fields.present? || @includes.any?
    end

    # Serialize a single ActiveRecord object
    def serialize_single_record
      options = {}
      options[:only] = @main_fields if @main_fields.present?
      options[:include] = build_include_options if @includes.any?

      @object.as_json(options)
    end

    # Serialize a collection (Array or ActiveRecord::Relation)
    def serialize_collection
      options = {}
      options[:only] = @main_fields if @main_fields.present?
      options[:include] = build_include_options if @includes.any?

      @object.as_json(options)
    end

    # Build include options for JSON serialization
    def build_include_options
      Presentable::IncludeBuilderService.new(@includes).build_options(@association_fields)
    end

    # Add pagination metadata to response
    def add_pagination(data)
      data[:current_page] = @pagy.page
      data[:total_pages] = @pagy.pages
      data[:total_count] = @pagy.count if @pagy.respond_to?(:count)
    end
  end
end
