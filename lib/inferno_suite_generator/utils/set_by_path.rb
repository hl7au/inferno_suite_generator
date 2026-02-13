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
      raise ArgumentError, "path_string cannot be nil or empty" if path_string.nil? || path_string.to_s.strip.empty?

      data = deep_copy_hash(hash_data)
      path = path_string.to_s.strip
      path = path.sub(/\A[A-Z][a-zA-Z]+\./, "") if path.match?(/\A[A-Z][a-zA-Z]+\./) # optional ResourceType. prefix
      segments = path.split(".")
      return data if segments.empty?

      current = data
      segments.each_with_index do |segment, i|
        key, index = parse_segment(segment)
        is_last = (i == segments.length - 1)

        if is_last
          set_value(current, key, index, data_to_set)
        else
          current = navigate_or_create(current, key, index)
        end
      end
      data
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
        parent[key] = {} unless parent.key?(key) && parent[key].is_a?(Hash)
        return parent[key]
      end
      parent[key] = [] unless parent.key?(key) && parent[key].is_a?(Array)
      arr = parent[key]
      (index - arr.length + 1).times { arr << {} } if index >= arr.length
      arr[index] = {} if arr[index].nil?
      arr[index]
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
