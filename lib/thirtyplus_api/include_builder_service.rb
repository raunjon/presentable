# frozen_string_literal: true

module ThirtyplusApi
  # Service for building ActiveRecord .includes() structures from various input formats
  # Handles conversion of dot notation (venue.events) to nested hash structures
  #
  # This service is used by FieldFilterService to build proper eager loading includes
  # that prevent N+1 queries while supporting complex nested associations.
  #
  # @example Simple associations
  #   builder = ThirtyplusApi::IncludeBuilderService.new(['event', 'venue'])
  #   builder.build_structure
  #   # => [:event, :venue]
  #
  # @example Nested associations with dot notation
  #   builder = ThirtyplusApi::IncludeBuilderService.new(['venue.events', 'venue.location'])
  #   builder.build_structure
  #   # => [{ venue: [:events, :location] }]
  #
  # @example Deep nesting
  #   builder = ThirtyplusApi::IncludeBuilderService.new(['venue.events.organizer'])
  #   builder.build_structure
  #   # => [{ venue: { events: :organizer } }]
  #
  # @example Mixed simple and nested
  #   builder = ThirtyplusApi::IncludeBuilderService.new(['event', 'venue.location'])
  #   builder.build_structure
  #   # => [:event, { venue: :location }]
  #
  class IncludeBuilderService
    # Initialize the include builder
    #
    # @param includes_array [Array<String, Symbol, Hash>] Array of association names or hashes
    def initialize(includes_array)
      @includes = includes_array || []
    end

    # Build the includes structure suitable for ActiveRecord .includes()
    #
    # Converts various input formats into the proper nested hash structure
    # that ActiveRecord expects for eager loading associations.
    #
    # @return [Array<Symbol, Hash>] Properly formatted includes array
    def build_structure
      structured = {}
      simple_includes = []

      @includes.each do |include_item|
        if include_item.is_a?(Hash)
          merge_hash_include(structured, include_item)
        elsif include_item.to_s.include?('.')
          merge_nested_include(structured, include_item)
        else
          add_simple_include(simple_includes, structured, include_item)
        end
      end

      combine_results(simple_includes, structured)
    end

    # Build include options with field filtering
    # Used for JSON rendering with only specific fields
    # Converts to Rails .as_json() format with :include keys for nesting
    #
    # @param association_fields [Hash] Map of association names to field arrays
    # @return [Hash] Include options with :only selectors and :include for nesting
    #
    # @example Simple association
    #   builder.build_options({'event' => ['id', 'title']})
    #   # => { event: { only: ['id', 'title'] } }
    #
    # @example Nested association
    #   builder = ThirtyplusApi::IncludeBuilderService.new(['payment_message.whatsapp_conversation'])
    #   builder.build_options({})
    #   # => { payment_message: { include: :whatsapp_conversation } }
    def build_options(association_fields = {})
      result = {}

      @includes.each do |item|
        if item.is_a?(Hash)
          merge_hash_options(result, item)
        elsif item.to_s.include?('.')
          # Nested association - convert to :include format for .as_json()
          merge_nested_options(result, item)
        else
          # Simple association
          add_field_options(result, item, association_fields)
        end
      end

      result.any? ? result : @includes
    end

    private

    # Merge a hash include into the structured result
    def merge_hash_include(structured, hash_item)
      hash_item.each do |key, value|
        if structured[key]
          structured[key] = deep_merge(structured[key], value)
        else
          structured[key] = value
        end
      end
    end

    # Merge a nested include (dot notation) into structured result
    # Example: "venue.events.organizer" becomes { venue: { events: :organizer } }
    def merge_nested_include(structured, nested_item)
      parts = nested_item.to_s.split('.')
      root = parts.first.to_sym

      nested_value = build_nested_value(parts[1..])

      if structured[root]
        structured[root] = deep_merge(structured[root], nested_value)
      else
        structured[root] = nested_value
      end
    end

    # Build nested value from parts array
    # Example: ['events', 'organizer'] becomes { events: :organizer }
    def build_nested_value(parts)
      return parts.first.to_sym if parts.length == 1

      # Build from innermost to outermost
      parts.reverse.reduce(nil) do |nested, part|
        nested.nil? ? part.to_sym : { part.to_sym => nested }
      end
    end

    # Add a simple include if not already in structured
    def add_simple_include(simple_includes, structured, item)
      symbol_item = item.to_s.to_sym
      simple_includes << symbol_item unless structured.key?(symbol_item)
    end

    # Combine simple and structured includes into final result
    def combine_results(simple_includes, structured)
      result = simple_includes.dup

      structured.each do |key, value|
        result << { key => value }
      end

      result
    end

    # Deep merge two hash/symbol values
    # Handles merging nested hash structures for associations
    def deep_merge(value1, value2)
      # If either is a symbol, prefer the hash structure
      return value2 if value1.is_a?(Symbol)
      return value1 if value2.is_a?(Symbol)

      # Both are hashes - merge recursively
      return value1.merge(value2) unless value1.is_a?(Hash) && value2.is_a?(Hash)

      value1.merge(value2) do |_key, old_val, new_val|
        deep_merge(old_val, new_val)
      end
    end

    # Merge hash options for include configuration
    def merge_hash_options(result, hash_item)
      hash_item.each do |key, value|
        if result[key]
          result[key] = deep_merge_options(result[key], value)
        else
          result[key] = value
        end
      end
    end

    # Merge nested association (dot notation) into options for .as_json()
    # Converts "payment_message.whatsapp_conversation" to
    # { payment_message: { include: :whatsapp_conversation } }
    def merge_nested_options(result, nested_item)
      parts = nested_item.to_s.split('.')
      root = parts.first.to_sym

      # Build nested :include structure for .as_json()
      nested_value = build_nested_include_value(parts[1..])

      if result[root]
        result[root] = deep_merge_options(result[root], { include: nested_value })
      else
        result[root] = { include: nested_value }
      end
    end

    # Build nested include value for .as_json() format
    # ['whatsapp_conversation'] => :whatsapp_conversation
    # ['venue', 'location'] => { venue: { include: :location } }
    def build_nested_include_value(parts)
      if parts.length == 1
        parts.first.to_sym
      else
        first = parts.first.to_sym
        rest = build_nested_include_value(parts[1..])
        { first => { include: rest } }
      end
    end

    # Add field filtering options for an association
    def add_field_options(result, association, association_fields)
      association_sym = association.to_sym
      fields = association_fields[association.to_s]

      if fields&.any?
        # Add 'id' to ensure associations work
        only_fields = (fields + ['id']).uniq

        if result[association_sym]
          result[association_sym] = deep_merge_options(
            result[association_sym],
            { only: only_fields }
          )
        else
          result[association_sym] = { only: only_fields }
        end
      else
        # No field filtering, just include association
        result[association_sym] ||= {}
      end
    end

    # Deep merge options hashes
    # Special handling for :include key to combine multiple associations
    def deep_merge_options(hash1, hash2)
      return hash2 if hash1.is_a?(Symbol)
      return hash1 if hash2.is_a?(Symbol)
      return hash1.merge(hash2) unless hash1.is_a?(Hash) && hash2.is_a?(Hash)

      hash1.merge(hash2) do |key, old_val, new_val|
        if old_val.is_a?(Hash) && new_val.is_a?(Hash)
          deep_merge_options(old_val, new_val)
        elsif old_val.is_a?(Array) && new_val.is_a?(Array)
          (old_val + new_val).uniq
        elsif key == :include
          # Special handling for :include key - combine multiple associations into array
          merge_include_values(old_val, new_val)
        else
          new_val
        end
      end
    end

    # Merge two :include values into an array
    # :events + :location => [:events, :location]
    # [:events] + :location => [:events, :location]
    # {:events => {...}} + :location => [{:events => {...}}, :location]
    def merge_include_values(val1, val2)
      # Convert both to arrays
      arr1 = val1.is_a?(Array) ? val1 : [val1]
      arr2 = val2.is_a?(Array) ? val2 : [val2]

      # Combine and return
      (arr1 + arr2).uniq
    end
  end
end
