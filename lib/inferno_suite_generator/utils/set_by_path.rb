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
    # @return [Hash] New hash with the value set at the path
    def self.set_by_path(hash_data, path_string, data_to_set)
      return hash_data if hash_data.nil?

      validate_path_string!(path_string)

      data = deep_copy_hash(hash_data)
      segments = normalize_path(path_string).split(".")
      return data if segments.empty?

      apply_path_segments(data, segments, data_to_set)
      data
    end

    def self.validate_path_string!(path_string)
      return unless path_string.nil? || path_string.to_s.strip.empty?

      raise ArgumentError, "path_string cannot be nil or empty"
    end

    def self.normalize_path(path_string)
      path = path_string.to_s.strip
      path = path.sub(/\A[A-Z][a-zA-Z]+\./, "") if path.match?(/\A[A-Z][a-zA-Z]+\./) # optional ResourceType. prefix
      path
    end

    def self.apply_path_segments(data, segments, data_to_set)
      current = data
      segments.each_with_index do |segment, i|
        key, index = parse_segment(segment)
        if i == segments.length - 1
          set_value(current, key, index, data_to_set)
        else
          current = navigate_or_create(current, key, index)
        end
      end
    end

    def self.multi_set_by_path(hash_data, path_string_and_data_array)
      result = deep_copy_hash(hash_data)
      path_string_and_data_array.each do |path_string, data|
        result = set_by_path(result, path_string, data)
      end
      result
    end

    # Parses a path segment like "name", "name[0]", "author[x]" into [key, index].
    # - "name" or "author[x]" => key, index nil
    # - "name[0]" => key "name", index 0
    def self.parse_segment(segment)
      segment = segment.to_s.strip
      # Numeric index: name[0], meta.profile[1]
      m = segment.match(/\A([^\[]+)\[(\d+)\]\z/)
      return [m[1].strip, m[2].to_i] if m
      # Choice type [x] or plain key: author[x], value[x], patient
      return [segment, nil] if segment.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*(\[x\])?\z/)

      raise ArgumentError, "Invalid path segment: #{segment.inspect}"
    end

    def self.set_value(parent, key, index, value)
      if index.nil?
        parent[key] = value
        return
      end
      parent[key] = [] unless parent.key?(key) && parent[key].is_a?(Array)
      arr = parent[key]
      (index - arr.length + 1).times { arr << nil } if index >= arr.length
      arr[index] = value
    end

    def self.navigate_or_create(parent, key, index)
      if index.nil?
        navigate_to_hash_at(parent, key)
      else
        navigate_to_hash_at_index(parent, key, index)
      end
    end

    def self.navigate_to_hash_at(parent, key)
      parent[key] = {} unless parent.key?(key) && parent[key].is_a?(Hash)
      parent[key]
    end

    def self.navigate_to_hash_at_index(parent, key, index)
      parent[key] = [] unless parent.key?(key) && parent[key].is_a?(Array)
      arr = parent[key]
      ensure_array_length(arr, index) { {} }
      arr[index] = {} if arr[index].nil?
      arr[index]
    end

    def self.ensure_array_length(arr, index)
      return unless index >= arr.length

      (index - arr.length + 1).times { arr << yield }
    end

    def self.deep_copy_hash(obj)
      case obj
      when Hash
        obj.transform_values { |v| deep_copy_hash(v) }
      when Array
        obj.map { |v| deep_copy_hash(v) }
      else
        obj
      end
    end
  end
end
