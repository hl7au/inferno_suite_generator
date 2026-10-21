# frozen_string_literal: true

module InfernoSuitePlugins
  module Read
    # Picks the groups whose CapabilityStatement declares the read interaction, with the data their read test
    # needs: the interaction expectation and, for first-class read profiles, the resource IDs input.
    #
    # A profile is a first-class read profile when its config sets "first_class_profile": "read" (under
    # configs.profiles.<profile url> or configs.resources.<resource type>). The input's default comes from
    # the constant read_ids.<snake_case resource type>, e.g. read_ids.practitioner_role.
    class Extractor < InfernoSuiteGenerator::Plugins::Extractor
      def extract
        return unless interaction

        {
          "interaction" => { "code" => "read", "expectation" => interaction[:expectation] },
          "ids_input" => ids_input
        }.compact
      end

      private

      def interaction
        @interaction ||= group_metadata.interactions.find { |item| item[:code] == "read" }
      end

      def ids_input
        return unless first_class_read?

        {
          "input_id" => "#{snake_case_resource}_ids",
          "title" => "#{resource} IDs",
          "description" => "Comma separated list of #{snake_case_resource.tr("_", " ")} IDs that in sum contain " \
                           "all MUST SUPPORT elements",
          "default" => context.config.constants["read_ids.#{snake_case_resource}"] || ""
        }
      end

      def first_class_read?
        context.config.resolve_value(group_metadata.profile_url, resource, "first_class_profile", "") == "read"
      end

      def resource
        group_metadata.resource
      end

      def snake_case_resource
        resource.gsub(/([a-z0-9])([A-Z])/, '\1_\2').downcase
      end
    end
  end
end
