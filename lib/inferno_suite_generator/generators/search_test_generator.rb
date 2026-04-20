# frozen_string_literal: true

require_relative "../utils/naming"
require_relative "basic_test_generator"
require_relative "../utils/registry"
require_relative "../utils/generator_utils"

module InfernoSuiteGenerator
  class Generator
    class SearchTestGenerator < BasicTestGenerator
      include GeneratorUtils

      class << self
        def generate(ig_metadata, base_output_dir)
          ig_metadata.groups
                     .reject do |group|
                       Registry.get(:config_keeper).exclude_resource?(group.profile_url, group.resource)
                     end
                     .select { |group| group.searches.present? }
                     .each do |group|
            group.searches.each { |search| new(group, search, base_output_dir, ig_metadata).generate }
          end
        end
      end

      attr_accessor :group_metadata, :search_metadata, :base_output_dir, :ig_metadata

      self.template_type = TEMPLATE_TYPES[:SEARCH]

      def initialize(group_metadata, search_metadata, base_output_dir, ig_metadata)
        self.group_metadata = group_metadata
        self.search_metadata = search_metadata
        self.base_output_dir = base_output_dir
        self.ig_metadata = ig_metadata
      end

      def search_identifier
        search_metadata[:names].join("_").tr("-", "_")
      end

      def search_title
        search_identifier.camelize
      end

      def conformance_expectation
        search_metadata[:expectation]
      end

      def first_search_for_patient_by_patient_id
        first_search? && resource_type == "Patient" && search_metadata[:names].first == "_id"
      end

      def first_search?
        group_metadata.searches.first == search_metadata
      end

      def fixed_value_search?
        first_search_not_patient? || fixed_value_search_from_config?
      end

      def fixed_value_search_from_config?
        fixed_values = Registry.get(:config_keeper).fixed_values_to_search(group_metadata.profile_url, group_metadata.resource)
        search_params = search_metadata[:names]

        fixed_values.any? { |fixed_value| search_params.include?(fixed_value) }
      end

      def first_search_not_patient?
        first_search? && search_metadata[:names] != ["patient"] &&
          !group_metadata.delayed? && resource_type != "Patient"
      end

      def fixed_value_search_param_name
        (search_metadata[:names] - [:patient]).first
      end

      def search_param_name_string
        search_metadata[:names].join(" + ")
      end

      def needs_patient_id?
        search_metadata[:names].include?("patient")
      end

      def search_param_names
        search_params.map { |param| param[:name] }
      end

      def search_param_names_array
        array_of_strings(search_param_names)
      end

      def path_for_value(path)
        path == "class" ? "local_class" : path
      end

      def required_comparators_for_param(name)
        search_definition(name)[:comparators].select { |_comparator, expectation| expectation == "SHALL" }
      end

      def optional?
        conformance_expectation != "SHALL"
      end

      def search_definition(name)
        group_metadata.search_definitions[name.to_sym]
      end

      def saves_delayed_references?
        first_search? && group_metadata.delayed_references.present?
      end

      def possible_status_search?
        search_metadata[:names].none? { |name| name.include? "status" } &&
          group_metadata.search_definitions.keys.any? { |key| key.to_s.include? "status" }
      end

      def token_search_params_string
        array_of_strings(token_search_params)
      end

      def required_multiple_or_search_params
        @required_multiple_or_search_params ||=
          search_param_names.select do |name|
            search_definition(name)[:multiple_or] == "SHALL"
          end
      end

      def optional_multiple_or_search_params
        @optional_multiple_or_search_params ||=
          search_param_names.select do |name|
            search_definition(name)[:multiple_or] == "SHOULD"
          end
      end

      def required_multiple_or_search_params_string
        array_of_strings(required_multiple_or_search_params)
      end

      def optional_multiple_or_search_params_string
        array_of_strings(optional_multiple_or_search_params)
      end

      def optional_multiple_and_search_params
        @optional_multiple_and_search_params ||=
          search_param_names.select do |name|
            search_definition(name)[:multiple_and] == "SHOULD"
          end
      end

      def required_multiple_and_search_params
        @required_multiple_and_search_params ||=
          search_param_names.select do |name|
            search_definition(name)[:multiple_and] == "SHALL"
          end
      end

      def optional_multiple_and_search_params_string
        array_of_strings(optional_multiple_and_search_params)
      end

      def required_multiple_and_search_params_string
        array_of_strings(required_multiple_and_search_params)
      end

      def required_comparators_string
        array_of_strings(required_comparators.keys)
      end

      def test_reference_variants?
        return true if resource_type == "PractitionerRole" && search_param_names.include?("practitioner")

        first_search? && search_param_names.include?("patient")
      end

      def test_medication_inclusion?
        Registry.get(:config_keeper).test_medication_inclusion?(group_metadata.profile_url, group_metadata.resource)
      end

      def test_post_search?
        first_search?
      end

      def includes_from_config
        config = Registry.get(:config_keeper)
        search_names = search_metadata[:names].sort
        include_cases = config.extra_searches(group_metadata.profile_url, group_metadata.resource).select { |search| search["type"] == "include" }
        include_case = include_cases.find { |include_case| include_case["names"].sort == search_names }

        return [] unless include_case

        [{
           "parameter" => include_case["param"],
           "target_resource" => include_case["target_resource"],
           "paths" => include_case["paths"]
         }]
      end
      def includes
        includes_from_config
      end

      def search_properties
        {}.tap do |properties|
          properties[:first_search] = "true" if first_search?
          properties[:fixed_value_search] = "true" if fixed_value_search?
          properties[:resource_type] = "'#{resource_type}'"
          properties[:search_param_names] = search_param_names_array
          properties[:saves_delayed_references] = "true" if saves_delayed_references?
          properties[:possible_status_search] = "true" if possible_status_search?
          properties[:test_medication_inclusion] = "true" if test_medication_inclusion?
          properties[:token_search_params] = token_search_params_string if token_search_params.present?
          properties[:test_reference_variants] = "true" if test_reference_variants?
          properties[:params_with_comparators] = required_comparators_string if required_comparators.present?
          properties[:test_post_search] = "true" if first_search?
          properties[:first_search_for_patient_by_patient_id] = "true" if first_search_for_patient_by_patient_id
        end
      end

      def reference_search_description
        return "" unless test_reference_variants?

        <<~REFERENCE_SEARCH_DESCRIPTION
          This test verifies that the server supports searching by reference using
          the form `#{search_param_names.first}=[id]` as well as `#{search_param_names.first}=#{search_param_names.first.capitalize}/[id]`. The two
          different forms are expected to return the same number of results. #{Registry.get(:config_keeper).title} requires that both forms are supported by #{Registry.get(:config_keeper).title} responders.
        REFERENCE_SEARCH_DESCRIPTION
      end

      def first_search_description
        return "" unless first_search?

        <<~FIRST_SEARCH_DESCRIPTION
          Because this is the first search of the sequence, resources in the
          response will be used for subsequent tests.
        FIRST_SEARCH_DESCRIPTION
      end

      def medication_inclusion_description
        return "" unless test_medication_inclusion?

        <<~MEDICATION_INCLUSION_DESCRIPTION
          If any #{resource_type} resources use external references to
          Medications, the search will be repeated with
          `_include=#{resource_type}:medication`.
        MEDICATION_INCLUSION_DESCRIPTION
      end

      def post_search_description
        return "" unless test_post_search?

        <<~POST_SEARCH_DESCRIPTION
          Additionally, this test will check that GET and POST search methods
          return the same number of results. Search by POST is required by the
          FHIR R4 specification, and these tests interpret search by GET as a
          requirement of #{Registry.get(:config_keeper).title} #{group_metadata.version}.
        POST_SEARCH_DESCRIPTION
      end

      def description
        <<~DESCRIPTION.gsub(/\n{3,}/, "\n\n")
          A server #{conformance_expectation} support searching by
          #{search_param_name_string} on the #{resource_type} resource. This test
          will pass if resources are returned and match the search criteria. If
          none are returned, the test is skipped.

          #{medication_inclusion_description}
          #{reference_search_description}
          #{first_search_description}
          #{post_search_description}

          #{capability_statement_reference_string}
        DESCRIPTION
      end

      def search_method
        Registry.get(:config_keeper).get_executor(
          group_metadata.profile_url, group_metadata.resource, search_metadata[:names].first
        )
      end

      def ids_input_data
        return unless needs_ids_input?

        data = Registry.get(:config_keeper).search_test_ids_inputs(group_metadata.profile_url, resource_type,
                                                                   search_param_names)

        {
          id: data["input_id"].to_sym,
          title: data["title"],
          description: data["description"],
          default: data["default"]
        }
      end

      def keep_all_search_results?
        Registry.get(:config_keeper).keep_all_search_results(group_metadata.profile_url, resource_type)
      end

      private

      def needs_ids_input?
        Registry.get(:config_keeper).first_class_search?(group_metadata.profile_url, resource_type, search_param_names)
      end
    end
  end
end
