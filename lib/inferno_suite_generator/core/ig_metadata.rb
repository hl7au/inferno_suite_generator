# frozen_string_literal: true

module InfernoSuiteGenerator
  class Generator
    class IGMetadata
      attr_accessor :ig_version, :ig_id, :ig_title, :ig_module_name_prefix, :ig_test_id_prefix, :groups

      def reformatted_version
        @reformatted_version ||= ig_version.delete(".").tr("-", "_")
      end

      def ordered_groups
        @ordered_groups ||=
          [patient_group] + non_delayed_groups + delayed_groups
      end

      def patient_group
        @patient_group ||=
          groups.find { |group| group.resource == "Patient" }
      end

      def delayed_groups
        @delayed_groups ||=
          groups.select(&:delayed?)
      end

      def non_delayed_groups
        @non_delayed_groups ||=
          groups.reject(&:delayed?) - [patient_group]
      end

      def delayed_profiles
        @delayed_profiles ||=
          delayed_groups.map(&:profile_url)
      end

      def postprocess_groups(ig_resources)
        groups.each do |group|
          group.add_delayed_references(delayed_profiles, ig_resources)
        end
      end

      def patch_interaction_exists?
        groups.any? { |group| group.interactions.find { |interaction| interaction[:code] == "patch" }.present? }
      end

      def to_hash
        {
          ig_id:,
          ig_title:,
          ig_module_name_prefix:,
          ig_test_id_prefix:,
          ig_version:,
          groups: groups.map(&:to_hash)
        }
      end
      
      def search_groups
        groups.select { |group| group.searches.present? }
      end

      def resource_types_for_references
        groups.flat_map { |group| group.references.map { |reference| reference[:resource_types] } }.flatten.uniq.compact
      end
    end
  end
end
