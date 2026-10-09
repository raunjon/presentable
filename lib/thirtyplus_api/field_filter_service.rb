# frozen_string_literal: true

module ThirtyplusApi
  # Service for filtering API response fields and optimizing database queries
  # Handles the ?fields= and ?includes= query parameters for API endpoints
  #
  # This service provides GraphQL-like field selection for REST APIs:
  # - Allows clients to request specific fields only
  # - Supports nested association field selection (dot notation)
  # - Automatically optimizes queries with .select() and .includes()
  # - Prevents N+1 queries by eager loading associations
  #
  # @example Basic usage
  #   # GET /api/v1/entries?fields=id,name,email
  #   service = ThirtyplusApi::FieldFilterService.new(params, Entry.all)
  #   filtered_query = service.call
  #   # => SELECT id, name, email FROM entries
  #
  # @example With associations
  #   # GET /api/v1/entries?fields=id,name,event.title&includes=event
  #   service = ThirtyplusApi::FieldFilterService.new(params, Entry.all)
  #   filtered_query = service.call
  #   # => SELECT id, name, event_id FROM entries INCLUDE events (SELECT id, title)
  #
  # @example In controller
  #   def index
  #     entries = Entry.all
  #     entries = ThirtyplusApi::FieldFilterService.new(params, entries).call
  #     render json: entries
  #   end
  #
  class FieldFilterService
    # Raised when ?fields= names something that is not a real column (or a
    # related record's column, for dot notation). Presentable turns it into a
    # 400, so the names never reach the database.
    class UnknownFieldsError < StandardError
      attr_reader :fields

      def initialize(fields)
        @fields = fields
        super("Unknown fields: #{fields.join(', ')}")
      end
    end

    # Raised when ?includes= names something that is not a real association
    # (following each step of dot notation). Presentable turns it into a 400.
    # Without this check, as_json(include:) calls the name as a method on a
    # single record, so ?includes=destroy would delete it.
    class UnknownIncludesError < StandardError
      attr_reader :includes

      def initialize(includes)
        @includes = includes
        super("Unknown includes: #{includes.join(', ')}")
      end
    end

    attr_reader :main_fields, :association_fields, :includes

    # Initialize the field filter service
    #
    # @param params [ActionController::Parameters] Request params containing 'fields' and 'includes'
    # @param query [ActiveRecord::Relation, ActiveRecord::Base] The query or model to filter
    # @param includes [Array<String>] Optional pre-parsed includes array
    def initialize(params, query, includes: nil)
      @params = params
      @query = query
      @includes = includes || []
      @main_fields = []
      @association_fields = {}
    end

    # Apply field filtering and eager loading to the query
    #
    # @return [ActiveRecord::Relation, ActiveRecord::Base] Filtered query with .select() and .includes() applied
    def call
      return @query unless should_filter?

      parse_fields
      validate_fields!
      validate_includes!
      apply_field_selection
      apply_eager_loading

      @query
    end

    private

    # When neither ?fields= nor ?includes= is present nothing is validated, but
    # @includes can then only have been set by controller code, never by the
    # client (Presentable#set_includes reads only params[:includes]).
    # Check if filtering should be applied
    def should_filter?
      @params[:fields].present? || @params[:includes].present?
    end

    # Parse the fields parameter into main fields and association fields
    # Handles both simple fields (id, name) and nested fields (event.title)
    def parse_fields
      return unless @params[:fields].present?

      fields = @params[:fields].split(',').map(&:strip).reject(&:empty?)
      # Always include ID for associations to work
      # fields << 'id' unless fields.include?('id')

      fields.each do |field|
        if field.include?('.')
          parse_association_field(field)
        else
          @main_fields << 'id' unless fields.include?('id')
          @main_fields << field
        end
      end
      
    end

    # Parse an association field like "event.title" or "venue.location.city"
    def parse_association_field(field)
      association, attribute = field.split('.', 2)

      # Store the attribute for this association
      @association_fields[association] ||= []
      @association_fields[association] << attribute

      # Ensure root association is included
      root_association = association.split('.').first
      @includes << root_association unless @includes.include?(root_association)
    end

    # Reject any requested field that isn't a real column, before it can reach
    # .select (raw SQL) or as_json. Only relations and records are checked:
    # they are the only objects whose fields are sent to the database.
    def validate_fields!
      model = filterable_model
      return unless model

      unknown = @main_fields.reject { |field| model.column_names.include?(field) }
      @association_fields.each do |association, attributes|
        attributes.each do |attribute|
          path = "#{association}.#{attribute}".split('.', -1)
          unknown << path.join('.') unless valid_field_path?(model, path)
        end
      end

      raise UnknownFieldsError, unknown.uniq if unknown.any?
    end

    def filterable_model
      return @query.model if @query.is_a?(ActiveRecord::Relation)
      return @query.class if @query.is_a?(ActiveRecord::Base)

      nil
    end

    # Reject any ?includes= name that isn't a real association path, before
    # it reaches .includes or as_json(include:). Hash entries can only come
    # from controller code, not the query string, so they are left alone.
    def validate_includes!
      model = filterable_model
      return unless model

      unknown = @includes.filter_map do |include_item|
        next unless include_item.is_a?(String) || include_item.is_a?(Symbol)

        name = include_item.to_s
        name unless association_target(model, name.split('.', -1))
      end

      raise UnknownIncludesError, unknown.uniq if unknown.any?
    end

    # path is association names followed by a column, e.g. ["event", "venue", "name"].
    def valid_field_path?(model, path)
      *associations, column = path
      target = association_target(model, associations)
      !target.nil? && !column.empty? && target.column_names.include?(column)
    end

    # Follows association names from model and returns the model at the end,
    # or nil if any name is empty, unknown or polymorphic.
    def association_target(model, names)
      return nil if names.empty?

      names.each do |name|
        return nil if name.empty?

        reflection = model.reflect_on_association(name.to_sym)
        return nil if reflection.nil? || reflection.polymorphic?

        model = reflection.klass
      end
      model
    end

    # Apply field selection to the query using .select()
    # Also automatically includes foreign keys for associations
    def apply_field_selection
      return unless @main_fields.any?

      # Include foreign keys for associations
      foreign_keys = resolve_foreign_keys
      selected_fields = (@main_fields + foreign_keys).uniq

      if @query.is_a?(ActiveRecord::Base)
        # Single record - store for later JSON rendering
        @main_fields = selected_fields
      else
        # Query/relation - apply select
        @query = @query.select(selected_fields)
      end
    end

    # Resolve foreign keys needed for associations
    # Automatically includes foreign keys so associations don't break
    def resolve_foreign_keys
      return [] unless @includes.any?

      model_class = query_model_class
      foreign_keys = []

      @includes.each do |association_name|
        # Skip hashes and nested associations
        next if association_name.is_a?(Hash) || association_name.to_s.include?('.')

        root_association = association_name.to_s.split('.').first
        reflection = model_class.reflect_on_association(root_association.to_sym)

        if reflection && has_foreign_key?(reflection)
          foreign_keys << reflection.foreign_key
        end
      end

      foreign_keys
    end

    # Get the model class from query
    def query_model_class
      if @query.respond_to?(:model)
        @query.model
      else
        @query.class
      end
    end

    # Check if reflection has a foreign key in the table
    def has_foreign_key?(reflection)
      foreign_key = reflection.foreign_key
      @query.respond_to?(:column_names) && @query.column_names.include?(foreign_key)
    end

    # Apply eager loading to prevent N+1 queries
    # Uses the IncludeBuilderService to handle complex nested associations
    def apply_eager_loading
      return unless @includes.any?
      return if @query.is_a?(ActiveRecord::Base) # Skip for single records

      # Build proper includes structure
      includes_structure = ThirtyplusApi::IncludeBuilderService.new(@includes).build_structure

      @query = @query.includes(includes_structure) if includes_structure.present?
    end
  end
end
