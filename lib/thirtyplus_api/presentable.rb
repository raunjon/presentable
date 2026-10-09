# frozen_string_literal: true

module ThirtyplusApi
  # = ThirtyplusApi::Presentable
  #
  # Controller concern that renders ActiveRecord results in the standard
  # ThirtyPlus JSON envelope, with Pagy pagination and client-controlled field
  # selection (?fields=) and eager loading (?includes=).
  #
  # == Setup
  #
  # Include it once in your API base controller. It brings in Pagy::Backend
  # itself and adds a +before_action :set_includes+, so nothing else is needed:
  #
  #   module Api
  #     module V1
  #       class BaseController < Api::BaseController
  #         include ThirtyplusApi::Presentable
  #       end
  #     end
  #   end
  #
  # == In controllers
  #
  #   class LeadsController < Api::V1::BaseController
  #     # Collections: paginate + present in one call.
  #     def index
  #       set_pagy_and_present(Lead.where(tenant_id: current_tenant_id))
  #     end
  #
  #     # Single records.
  #     def show
  #       present Lead.find(params[:id])
  #     end
  #
  #     # Created records: pass nil for pagy to reach the status argument.
  #     def create
  #       lead = Lead.new(lead_params)
  #       lead.save ? present(lead, nil, :data, 201) : render_validation_errors(lead.errors)
  #     end
  #   end
  #
  # Extra top-level keys:
  #   set_pagy_and_present(leads, { filters_applied: true })     # paginated
  #   present_object_with_metadata(stats, { generated_at: now })  # not paginated
  #
  # A different wrapper key:
  #   present leads, nil, :leads   # => { leads: [...], success: true }
  #
  # == Query parameters (for API clients)
  #
  # page        Page number, 1-based. Default 1.
  # page=0      No pagination: return every record, with no pagination keys.
  # per_page    Page size. Default 10.
  # fields      Comma-separated columns to return. +id+ is always added:
  #               ?fields=name,email           => { id, name, email }
  # fields with dot notation limits an association's columns (and loads it):
  #               ?fields=name,event.title     => { id, name, event: { id, title } }
  #             Every name must be a real column (for dot notation: a real
  #             association, then a real column on it). Anything else renders
  #             400 { error: { value: "fields", message: "Unknown fields: ..." } }
  #             and never reaches the database.
  # includes    Comma-separated associations to nest, dot notation for depth:
  #               ?includes=event,event.venue
  #             Every name must be a real association (each step, for dot
  #             notation). Anything else renders
  #             400 { error: { value: "includes", message: "Unknown includes: ..." } }
  #             before eager loading or serialization (no association or
  #             method is called).
  # X-Content-Type header containing "xml" renders XML instead of JSON.
  #
  # == Response shapes
  #
  # Paginated collection (set_pagy_and_present):
  #   { "data": [...], "success": true,
  #     "current_page": 1, "total_pages": 3, "total_count": 25 }
  #
  # Single record, or page=0, or present without pagy:
  #   { "data": {...} | [...], "success": true }
  #
  # Apart from the 400 for unknown ?fields= / ?includes= names, errors are
  # not rendered here; use ThirtyplusApi::ErrorResponses
  # (render_validation_errors, record_not_found, ...).
  #
  # == Behavior to know about (current, not yet fixed)
  #
  # - SECURITY: +as_json(only:)+ overrides a model's +as_json(except:)+, so a
  #   real column the model hides (for example TenantCredential#credential_data)
  #   is returned if requested by name. Do not present models with secret
  #   columns until this is fixed.
  # - ?fields= on an Array or Hash (for example a page past the end, or a
  #   present({...}) payload) raises ArgumentError (500).
  # - On create/update, an unknown ?fields= or ?includes= name renders 400
  #   after the write has already happened.
  # - Polymorphic associations are rejected by ?fields= and ?includes= (their
  #   target class can't be checked).
  # - per_page has no upper bound.
  # - A page past the end returns { data: [], success: true } with no
  #   pagination keys (the Pagy::OverflowError rescue has no pagy object).
  # - Metadata keys are merged last, so a key named :data or :success
  #   overwrites the real value.
  # - Foreign keys needed to load ?fields= associations are SELECTed but not
  #   rendered unless also requested.
  # - Set @force_fields (an Array of column names) in an action to always
  #   return those columns; it only takes effect when ?fields= is present.
  module Presentable
    extend ActiveSupport::Concern

    # Presentable#pagy overrides Pagy::Backend#pagy and calls super, so the
    # backend must sit below this module in the ancestor chain.
    include Pagy::Backend

    # bad_request renders the 400 for unknown ?fields= names.
    include ErrorResponses

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
      begin
        filtered_object = filter_service.call
      rescue ThirtyplusApi::FieldFilterService::UnknownFieldsError => e
        return bad_request(e.message, 'fields')
      rescue ThirtyplusApi::FieldFilterService::UnknownIncludesError => e
        return bad_request(e.message, 'includes')
      end

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
      @includes = params[:includes] ? params[:includes].split(',').map(&:strip).reject(&:empty?) : []
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
