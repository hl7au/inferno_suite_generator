# frozen_string_literal: true

module InfernoSuitePlugins
  module ProfileRead
    # The read data for one group: its profile, what the CapabilityStatement expects of read, and the ids of the
    # IG examples that claim the profile in meta.profile. Those ids become the generated test's default input.
    # Returns nil, leaving the group out, when the declared_only option is set and the group has no read
    # interaction.
    class Extractor < InfernoSuiteGenerator::Plugins::Extractor
      def extract
        return if declared_only? && read_interaction.empty?

        {
          "resource_type" => group_metadata.resource,
          "profile_url" => group_metadata.profile_url,
          "profile_version" => group_metadata.profile_version,
          "expectation" => read_interaction[:expectation],
          "example_ids" => example_ids,
          "validate" => context.options.fetch("validate", true)
        }
      end

      private

      def declared_only?
        context.options.fetch("declared_only", false)
      end

      # {} when the CapabilityStatement doesn't declare read.
      def read_interaction
        @read_interaction ||= Array(group_metadata.interactions)
                              .find { |interaction| interaction[:code] == "read" }.to_h
      end

      def example_ids
        examples = context.ig_resources&.get_resources_by_type(group_metadata.resource) || []
        examples.select { |resource| claims_profile?(resource) }.filter_map(&:id).uniq
      end

      # meta.profile may carry a version, as in http://example.org/StructureDefinition/patient|1.0.0.
      def claims_profile?(resource)
        Array(resource.meta&.profile).any? { |url| url.split("|").first == group_metadata.profile_url }
      end
    end
  end
end
