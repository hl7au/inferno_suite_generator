# frozen_string_literal: true

require_relative "../core/search_test_properties"
require_relative "search_test"

module InfernoSuiteGenerator
  module ChainedSearchTest
    extend Forwardable
    include SearchTest

    def_delegators "self.class", :metadata, :provenance_metadata, :properties
    def_delegators "properties",
                   :resource_type,
                   :search_param_names,
                   :attr_paths,
                   :target_identifier

    def extract_target_resource_from_chained_search_parameter(search_param)
      search_param.split(":").second.split(".").first
    end

    def get_resources_identifier(resources, target_identifier)
      if target_identifier
        resources.map do |r|
          r.identifier.filter { |idnt| idnt.system == target_identifier[:url] }
        end.flatten
      else
        resources.map(&:identifier).flatten
      end
    end

    def all_chain_identifier_values(patient_id_list, all_resources, chain_target, target_identifier)
      patient_id_list.map do |patient_id|
        next unless !all_resources.nil? && all_resources.include?(patient_id)

        resource_identifiers = get_resources_identifier(
          all_resources[patient_id].filter { |r| r.resourceType == chain_target },
          target_identifier
        )
        resource_identifiers.map do |identifier|
          { patient_id:, identifier: }
        end
      end.flatten
    end

    # Scratch keys that may hold the resources a chained search draws its identifiers from.
    #
    # Chained parameters are written as "<param>:<TargetType>.<element>", so the type being chained
    # to is whatever the search parameter names, and resource scratch is keyed by type. Two naming
    # conventions are in play and they only agree for single-word types: a generated test declares
    # its own scratch in snake_case (:practitioner_role_resources), while find_include_resources
    # keys included resources by downcase (:practitionerrole_resources). Both are checked rather
    # than guessing, since a chain target can be populated by either path.
    #
    # This used to be hardcoded to :patient_resources, which is right for a chain onto Patient and
    # empty for every other target, producing a test that could never find a candidate.
    def chain_target_scratch_keys(chain_target)
      [:"#{chain_target.underscore}_resources", :"#{chain_target.downcase}_resources"].uniq
    end

    def chain_target_resources(chain_target)
      chain_target_scratch_keys(chain_target).filter_map { |key| scratch[key] }.first
    end

    def run_chain_search_test
      chain_target = extract_target_resource_from_chained_search_parameter(search_param_names[0])

      run_chain_search_test_clean(
        search_param_names[0],
        patient_id_list,
        chain_target_resources(chain_target),
        attr_paths,
        target_identifier
      )
    end

    def pick_identifier_to_test(patient_id_list, all_patients_resources, search_param, target_identifier)
      all_chain_identifier_values(
        patient_id_list,
        all_patients_resources,
        extract_target_resource_from_chained_search_parameter(search_param),
        target_identifier
      ).sample
    end

    def returned_resources_is_valid?(resources_returned, identifier_to_test, attr_paths)
      existing_values = resources_returned.map do |rr|
        attr_paths.map do |attr_path|
          resolve_path(rr, attr_path).first.reference.split("/").second
        end
      end.flatten.compact.uniq

      existing_values.include? identifier_to_test[:patient_id]
    end

    def run_chain_search_test_clean(search_param, patient_id_list, all_patients_resources, attr_paths,
                                    target_identifier)
      passed = false

      chain_target = extract_target_resource_from_chained_search_parameter(search_param)

      identifiers_to_test = all_chain_identifier_values(
        patient_id_list,
        all_patients_resources,
        chain_target,
        target_identifier
      )

      # Without a candidate identifier there is nothing to search on, so no request is made. The
      # assertion below describes a response, so reporting it here would blame the server for a
      # result it was never asked to produce. Omit instead, and say which scratch was empty.
      if identifiers_to_test.compact.empty?
        omit "No #{chain_target} resource with a usable identifier was available to build the " \
             "#{search_param} search. Nothing was requested from the server."
      end

      identifiers_to_test.each do |identifier_to_test|
        next if identifier_to_test.nil?

        search_and_check_response({ search_param => "#{identifier_to_test[:identifier].system}|#{identifier_to_test[:identifier].value}" })
        result = returned_resources_is_valid?(fetch_all_bundled_resources.select do |resource|
                                                resource.resourceType == resource_type
                                              end, identifier_to_test, attr_paths)
        next unless result

        passed = true
        break
      end

      assert passed, "There is no reference to the target resource in the returned result"
    end
  end
end
