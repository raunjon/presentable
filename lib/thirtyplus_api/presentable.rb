# frozen_string_literal: true

module ThirtyplusApi
  # Concern for API V1 presentation methods
  # Provides field filtering, association eager loading, and pagination support
  #
  # Supports GraphQL-like field selection via query parameters:
  # - ?fields=id,name,email - Request specific fields only
  # - ?includes=event,venue - Include associations
  # - ?fields=id,name,event.title,venue.name - Request specific association fields
  #
  # @example Usage in controller
  #   class EntriesController < ThirtyplusApi::BaseController
  #     include ThirtyplusApi::V1::Presentable
  #
  #     def index
  #       entries = Entry.all
  #       present entries
  #     end
  #   end
  module Presentable
    extend ActiveSupport::Concern

    # Presentable#pagy overrides Pagy::Backend#pagy and calls super, so the
    # backend must sit below this module in the ancestor chain.
    include Pagy::Backend

    included do
      before_action :set_includes
    end

    # Override pagy to handle page=0 (return all results)
    #
    # @param object [ActiveRecord::Relation] The query to paginate
    # @param items [Integer] Items per page (default: 10)
    # @return [Array<Pagy, ActiveRecord::Relation>] Pagy object and paginated results
    def pagy(object, items: 10)
      if params[:page] == '0'
        return nil, object
      end
      super(object, limit: items)
    end

    # Present object with metadata
    # Convenience method for adding custom metadata to response
    #
    # @param object [Object] The object/collection to present
    # @param metadata [Hash] Additional metadata to include
    # @param key [Symbol] The key to wrap data in (default: :data)
    # @param status [Integer] HTTP status code (default: 200)
    #
    # @example
    #   present_object_with_metadata(@entries, { filters_applied: true })
    def present_object_with_metadata(object, metadata, key = :data, status = 200)
      set_metadata(metadata)
      present(object, nil, key, status)
    end

    # Present an object or collection with field filtering and pagination
    # This is the main method for rendering API responses
    #
    # Automatically applies:
    # - Field filtering based on ?fields= param
    # - Eager loading based on ?includes= param
    # - Pagination metadata if pagy object provided
    #
    # @param object [Object, ActiveRecord::Relation] Object or collection to present
    # @param pagy [Pagy, nil] Optional pagination object
    # @param key [Symbol] Key to wrap data in response (default: :data)
    # @param status [Integer] HTTP status code (default: 200)
    #
    # @example Simple usage
    #   def index
    #     entries = Entry.all
    #     present entries
    #   end
    #
    # @example With pagination
    #   def index
    #     pagy, entries = pagy(Entry.all)
    #     present entries, pagy
    #   end
    #
    # @example With custom key
    #   def index
    #     present @entries, nil, :entries
    #     # => { entries: [...], success: true }
    #   end
    def present(object, pagy = nil, key = :data, status = 200)
      # Apply field filtering and eager loading
      force_fields
      filter_service = ThirtyplusApi::FieldFilterService.new(params, object, includes: @includes)
      filtered_object = filter_service.call

      # Check for XML response
      if xml_response?
        render xml: { key => filtered_object, success: true }
        return
      end

      # Build JSON response
      builder = ThirtyplusApi::ResponseBuilderService.new(
        object: filtered_object,
        key: key,
        pagy: pagy,
        status: status,
        main_fields: filter_service.main_fields,
        includes: filter_service.includes,
        association_fields: filter_service.association_fields,
        metadata: metadata
      )
      render builder.to_json
    end

    # Set pagination and present results
    # Convenience method for common pagination + present pattern
    #
    # Handles Pagy::OverflowError gracefully by rendering empty array
    #
    # @param object [ActiveRecord::Relation] Query to paginate
    # @param metadata [Hash] Additional metadata to include
    #
    # @example
    #   def index
    #     entries = Entry.where(event_id: params[:event_id])
    #     set_pagy_and_present(entries)
    #   end
    #
    # @example With metadata
    #   set_pagy_and_present(entries, { total_revenue: calculate_revenue })
    def set_pagy_and_present(object, metadata = {})
      set_metadata(metadata)

      # Handle page=0 (no pagination)
      if params[:page] == '0'
        present object
        return
      end

      begin
        pagy_object, paginated = set_pagy(object)
        present paginated, pagy_object
      rescue Pagy::OverflowError
        # Page number too high - return empty with valid pagy
        present [], pagy_object
      end
    end

    # Parse includes parameter into array
    # Sets @includes instance variable for use by field filter service
    #
    # @example
    #   # GET /entries?includes=event,venue,date_entries
    #   set_includes
    #   @includes # => ['event', 'venue', 'date_entries']
    def set_includes
      @includes = params[:includes] ? params[:includes].split(',').map(&:strip) : []
    end

    private

    # Force inclusion of specific fields in response
    # Ensures @force_fields are always included in the response, even if not requested
    #
    # @example
    #   @force_fields = 'id,email'
    #   force_fields  # ensures id and email are always in response
    def force_fields
      return unless @force_fields.present?

      forced_fields = @force_fields

      if params[:fields].present?
        requested_fields = params[:fields].split(',').map(&:strip)
        merged_fields = (requested_fields + forced_fields).uniq
        params[:fields] = merged_fields.join(',')
      end
    end

    # Create pagy object with custom items per page
    #
    # @param object [ActiveRecord::Relation] Query to paginate
    # @return [Array<Pagy, ActiveRecord::Relation>] Pagy object and results
    def set_pagy(object)
      pagy(object, items: params[:per_page] || 10)
    end

    # Get current metadata hash
    #
    # @return [Hash] Current metadata or empty hash
    def metadata
      @metadata || {}
    end

    # Set metadata for response
    #
    # @param metadata [Hash] Metadata to include in response
    def set_metadata(metadata)
      @metadata = metadata
    end

    # Check if client requested XML response
    #
    # @return [Boolean] True if X-Content-Type header contains 'xml'
    def xml_response?
      content_type = request.headers['X-Content-Type']
      content_type&.include?('xml')
    end
  end
end
