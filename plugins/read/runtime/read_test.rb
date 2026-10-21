# frozen_string_literal: true

require "inferno_suite_generator/test_modules/basic_test"

module InfernoSuitePlugins
  module Read
    # Runs a generated read test inside Inferno. Copied into the generated suite at plugins/read/read_test.rb by
    # context.install_runtime, and required from each read test.
    #
    # The test reads either the resources earlier tests left in scratch, or the IDs entered in its IDs input
    # for first-class read profiles, then checks each response and keeps what it read in scratch for the
    # validation and must support tests that follow.
    module ReadTest
      include InfernoSuiteGenerator::BasicTest

      def all_scratch_resources
        scratch_resources[:all] ||= []
      end

      def perform_read_test(resources)
        resources_to_read = resources.blank? ? resources_from_ids_input : readable_resources(resources)
        assert resources_to_read.present?, "No #{resource_type} id found."
        resources_to_read.each { |resource_to_read| read_and_validate(resource_to_read) }
      end

      def read_and_validate(resource_to_read)
        id = resource_id(resource_to_read)
        fhir_read resource_type, id
        check_read_response(id)
        keep_read_resource
      end

      private

      def check_read_response(id)
        assert_response_status(200)
        assert_resource_type(resource_type)
        actual_id = resource.id
        assert actual_id.present? && actual_id == id, bad_resource_id_message(id)
      end

      def keep_read_resource
        all_scratch_resources << resource
        register_resource_id
        keep_resource(resource)
      end

      def resources_from_ids_input
        ids = ids_input_value
        skip no_resources_message if ids.blank?

        ids.split(",").map { |id| FHIR::Reference.new(reference: "#{resource_type}/#{id.strip}", type: resource_type) }
      end

      # The value of the <snake_case resource type>_ids input, "" when the test has no such input. Inferno
      # exposes inputs as methods, so checking for the method is how to tell whether the input exists.
      # :reek:ManualDispatch
      def ids_input_value
        method_name = "#{resource_type.gsub(/([a-z0-9])([A-Z])/, '\1_\2').downcase}_ids"
        respond_to?(method_name) ? send(method_name).to_s : ""
      end

      def readable_resources(resources)
        resources.select { |resource| readable?(resource) }.uniq { |resource| resource_id(resource) }
      end

      def readable?(resource)
        (resource.is_a?(resource_class) || resource.is_a?(FHIR::Reference)) && resource_id(resource).present?
      end

      # :reek:UtilityFunction
      def resource_id(resource)
        resource.is_a?(FHIR::Reference) ? resource.reference.split("/").last : resource.id
      end

      def resource_class
        FHIR.const_get(resource_type)
      end

      def bad_resource_id_message(expected_id)
        "Expected resource to have id: `#{expected_id.inspect}`, but found `#{resource.id.inspect}`"
      end

      def no_resources_message
        "There are no resources of the type #{resource_type} from previous tests, and you didn't provide IDs to " \
          "search."
      end
    end
  end
end
