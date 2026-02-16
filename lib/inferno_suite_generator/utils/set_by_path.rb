# frozen_string_literal: true

require_relative "../utils/basic_test_helpers"

module InfernoSuiteGenerator
  # Utility to set a value in a FHIR resource hash at a path defined by a FHIRPath-like expression.
  # Supports dot-separated segments, bracket indices (e.g. +name[0].family+), and choice-type [x]
  # (e.g. +note.author[x]+, +medication[x]+). ResourceType prefix is optional (e.g. +Patient.name+).
  module SetByPath
    include BasicTestHelpers

    # @param hash_data [Hash] FHIR resource as a hash (string or symbol keys)
    # @param path_string [String] FHIRPath-style path (e.g. "name[0].family", "meta.profile[0]", "resourceType")
    # @param data_to_set [Object] Value to set (any type)
    # @param datatype [String, nil] When the path contains a choice-type segment (e.g. +medication[x]+),
    #   pass the concrete FHIR property name to use instead (e.g. +"medicationReference"+).
    #   The value is set under that key rather than under +medication[x]+.
    # @return [Hash] New hash with the value set at the path
    # :reek:TooManyStatements
    def self.set_by_path(hash_data, path_string, data_to_set, datatype = nil)
      return hash_data unless hash_data

      validate_path_string!(path_string)
      data = deep_copy_hash(hash_data)
      segments = normalize_path(path_string).split(".")
      return data if segments.empty?

      apply_path_segments(data, segments, data_to_set, datatype)
      data
    end

    def self.validate_path_string!(path_string)
      return if path_string.to_s.strip != ""

      raise ArgumentError, "path_string cannot be nil or empty"
    end

    def self.normalize_path(path_string)
      path = path_string.to_s.strip
      path = path.sub(/\A[A-Z][a-zA-Z]+\./, "") if path.match?(/\A[A-Z][a-zA-Z]+\./) # optional ResourceType. prefix
      path
    end

    # When a segment is a choice type (key contains "[x]") and datatype is given, use datatype as the key.
    # :reek:TooManyStatements
    def self.apply_path_segments(data, segments, data_to_set, datatype = nil)
      segments_length = segments.length
      current = data
      segment_index = 0

      while segment_index < segments_length
        segment = segments[segment_index]
        key, index = parse_segment(segment)
        key = resolve_choice_key(key, datatype)
        is_last_segment = (segment_index == segments_length - 1)

        if is_last_segment
          set_value(current, key, { index:, value: data_to_set })
        else
          current = navigate_or_create(current, key, index)
        end
        segment_index += 1
      end
    end

    # For choice-type segments (e.g. "medication[x]"), use datatype as the key when provided.
    def self.resolve_choice_key(key, datatype)
      return key if datatype.nil? || datatype.to_s.strip.empty?
      return datatype.to_s.strip if key.to_s.include?("[x]")

      key
    end

    def self.multi_set_by_path(hash_data, path_string_and_data_array)
      result = deep_copy_hash(hash_data)
      path_string_and_data_array.each do |path_string, data, datatype|
        result = set_by_path(result, path_string, data, datatype)
      end
      result
    end

    # Parses a path segment like "name", "name[0]", "author[x]" into [key, index].
    # - "name" or "author[x]" => key, index nil
    # - "name[0]" => key "name", index 0
    def self.parse_segment(segment)
      segment = segment.to_s.strip
      # Numeric index: name[0], meta.profile[1]
      numeric_match = segment.match(/\A([^\[]+)\[(\d+)\]\z/)
      return [numeric_match[1].strip, numeric_match[2].to_i] if numeric_match
      # Choice type [x] or plain key: author[x], value[x], patient
      return [segment, nil] if segment.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*(\[x\])?\z/)

      raise ArgumentError, "Invalid path segment: #{segment.inspect}"
    end

    # assignment: { index: Integer|nil, value: Object }
    # :reek:NilCheck
    # :reek:TooManyStatements
    def self.set_value(parent, key, assignment)
      index = assignment[:index]
      value = assignment[:value]
      if index.nil?
        parent[key] = value
        return
      end
      slot = fetch_or_init_array(parent, key)
      arr_length = slot.length
      (index - arr_length + 1).times { slot << nil } if index >= arr_length
      slot[index] = value
    end

    def self.fetch_or_init_array(parent, key)
      slot = parent.fetch(key) { :_missing } # rubocop:disable Style/RedundantFetchBlock
      if slot == :_missing || !slot.is_a?(Array)
        slot = []
        parent[key] = slot
      end
      slot
    end

    # :reek:NilCheck
    def self.navigate_or_create(parent, key, index)
      if index.nil?
        navigate_to_hash_at(parent, key)
      else
        navigate_to_hash_at_index(parent, key, index)
      end
    end

    def self.navigate_to_hash_at(parent, key)
      slot = parent.fetch(key) { :_missing } # rubocop:disable Style/RedundantFetchBlock
      if slot == :_missing || !slot.is_a?(Hash)
        slot = {}
        parent[key] = slot
      end
      slot
    end

    def self.navigate_to_hash_at_index(parent, key, index)
      slot = fetch_or_init_array(parent, key)
      ensure_array_length(slot, index) { {} }
      slot[index] ||= {}
    end

    def self.ensure_array_length(arr, index)
      arr_length = arr.length
      return unless index >= arr_length

      (index - arr_length + 1).times { arr << yield }
    end

    def self.deep_copy_hash(obj)
      copier = ->(item) { deep_copy_hash(item) }
      case obj
      when Hash
        obj.transform_values(&copier)
      when Array
        obj.map(&copier)
      else
        obj
      end
    end
  end
end
