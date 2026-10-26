# frozen_string_literal: true

module InfernoSuitePlugins
  module ProfileRead
    # Runs in Inferno, mixed into every generated profile read test. The test class defines self.plugin_metadata,
    # its group's "profile_read" section of plugins.yml. Every id is read before the test fails, so one run lists
    # all the ids the server got wrong.
    module ProfileReadTest
      def run_profile_read_test(ids_input)
        ids = parse_ids(ids_input)
        skip_if ids.empty?, "No #{resource_type} ids to read. Enter the ids of resources that conform to " \
                            "#{profile_url}."

        failures = ids.filter_map { |id| read_failure(id) }
        assert failures.empty?, "#{failures.length} of #{ids.length} #{resource_type} reads failed:\n\n" \
                                "- #{failures.join("\n- ")}"
      end

      private

      def profile_read_metadata
        self.class.plugin_metadata
      end

      def resource_type
        profile_read_metadata.fetch("resource_type")
      end

      def profile_url
        profile_read_metadata.fetch("profile_url")
      end

      def versioned_profile_url
        version = profile_read_metadata["profile_version"]
        version.to_s.empty? ? profile_url : "#{profile_url}|#{version}"
      end

      def validate?
        profile_read_metadata.fetch("validate", true)
      end

      # Inferno gives the input as one string, e.g. "pat-1, pat-2".
      # :reek:UtilityFunction
      def parse_ids(ids_input)
        ids_input.to_s.split(/[\s,]+/).reject(&:empty?).uniq
      end

      # Reads one id. Returns why it failed, or nil when the server returned a valid resource with that id.
      def read_failure(id)
        fhir_read(resource_type, id)
        failure = status_failure(id) || type_failure(id) || id_failure(id)
        return failure if failure

        warn_unclaimed_profile(id)
        invalid_resource_failure(id) if validate?
      end

      def status_failure(id)
        status = response&.dig(:status)
        "#{id}: expected HTTP 200, got #{status || "no response"}" unless status == 200
      end

      def type_failure(id)
        returned = resource
        returned_type = returned.is_a?(FHIR::Model) ? returned.resourceType : "no resource"
        "#{id}: expected a #{resource_type}, got #{returned_type}" if returned_type != resource_type
      end

      # Compares the returned id with the one read, so it refers to the returned id more than to self.
      # :reek:FeatureEnvy
      def id_failure(id)
        returned_id = resource.id
        "#{id}: the server returned id #{returned_id.inspect}" if returned_id != id
      end

      def invalid_resource_failure(id)
        return if resource_is_valid?(profile_url: versioned_profile_url, message_prefix: "#{resource_type}/#{id}: ")

        "#{id}: doesn't conform to #{versioned_profile_url}"
      end

      # A resource can conform without claiming the profile, so this is a warning, not a failure.
      def warn_unclaimed_profile(id)
        claimed = Array(resource.meta&.profile).map { |url| url.split("|").first }
        return if claimed.include?(profile_url)

        warning "#{resource_type}/#{id} doesn't list #{profile_url} in meta.profile."
      end
    end
  end
end
