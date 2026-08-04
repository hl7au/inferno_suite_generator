# frozen_string_literal: true

require_relative "../utils/fhir_resource_navigation"
require_relative "../utils/assert_helpers"

module InfernoSuiteGenerator
  module ReferenceResolutionTest
    extend Forwardable
    include FHIRResourceNavigation
    include AssertHelpers

    def_delegators "self.class", :metadata

    def perform_reference_resolution_test(resources, rewrite_profile_url = {}, readable_resource_types = [])
      conditional_skip_with_msg resources.blank?, no_resources_skip_message

      pass if unresolved_references(resources, rewrite_profile_url, readable_resource_types).empty?

      # Distinguish the two ways a target can fail. A reference that was read
      # successfully but whose target does not conform to its profile is a
      # finding about the data, not an absence of data, and reporting it as a
      # skip hides it. Only a genuinely unreachable reference is a skip.
      #
      # Findings are matched back to the element they were collected for, so a
      # non-conformant target on an element that did resolve is never reported
      # as the reason a different element failed to resolve.
      findings = nonconformant_findings_for_unresolved_references

      assert findings.empty?, nonconformant_reference_message(findings)

      skip_with_msg "Could not resolve any Must Support references for #{unresolved_references_strings.join(", ")}"
    end

    def unresolved_references_strings(references = unresolved_references)
      unresolved_reference_hash =
        references.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |missing, hash|
          hash[missing[:path]] << missing[:target_profile]
        end
      unresolved_reference_hash.map do |path, profiles|
        "#{path} element: Reference#{"(#{profiles.join("|")})" unless profiles.first.empty?}"
      end
    end

    # Reported as a failure: the element did not resolve, and at least one of
    # its targets was read but did not conform.
    def nonconformant_findings_for_unresolved_references
      nonconformant_reference_findings.select do |finding|
        unresolved_references.any? { |pair| finding_matches_reference_pair?(finding, pair) }
      end
    end

    # Reported alongside the failure: the element did not resolve and nothing
    # was read, so there is no conformance finding to attach to it.
    def unreachable_unresolved_references
      unresolved_references.reject do |pair|
        nonconformant_reference_findings.any? { |finding| finding_matches_reference_pair?(finding, pair) }
      end
    end

    def nonconformant_reference_message(findings)
      described = findings.map do |finding|
        "#{finding[:path]} element: #{finding[:reference]} does not conform to #{finding[:target_profile]}"
      end

      message = "Must Support references resolved to targets that do not conform to their profile: " \
                "#{described.join(", ")}"

      unreachable = unresolved_references_strings(unreachable_unresolved_references)
      return message if unreachable.empty?

      "#{message}. Could not resolve any Must Support references for #{unreachable.join(", ")}"
    end

    def finding_matches_reference_pair?(finding, pair)
      finding[:target_profile] == pair[:target_profile] &&
        (finding[:path].nil? || finding[:path] == pair[:path])
    end

    def record_resolved_reference(reference, target_profile)
      saved_reference = resolved_references.find { |item| item[:reference] == reference.reference }

      if saved_reference.present?
        if target_profile.present? && !saved_reference[:profiles].include?(target_profile)
          saved_reference[:profiles] << target_profile
        end
      else
        saved_reference = {
          reference: reference.reference,
          profiles: []
        }

        saved_reference[:profiles] << target_profile if target_profile.present?
        resolved_references.add(saved_reference)
      end
    end

    def is_reference_resolved?(reference, target_profile)
      resolved_references.any? do |item|
        item[:reference] == reference.reference &&
          (
            target_profile.blank? || item[:profiles].include?(target_profile)
          )
      end
    end

    def resolved_references
      scratch[:resolved_references] ||= Set.new
    end

    # References that were read successfully but whose target failed validation
    # against its declared profile. Kept per test rather than in scratch, since
    # it describes this test's findings rather than session-wide state. Each
    # entry records the Must Support element it was collected for so findings
    # can be matched back to the element that failed to resolve.
    def nonconformant_reference_findings
      @nonconformant_reference_findings ||= []
    end

    def record_nonconformant_reference_target(path, reference, target_profile)
      finding = { path:, reference: reference.reference, target_profile: }
      nonconformant_reference_findings << finding unless nonconformant_reference_findings.include?(finding)
    end

    def no_resources_skip_message
      "No #{resource_type} resources appear to be available. " \
        "Please use patients with more information."
    end

    def must_support_references
      metadata.must_supports[:elements].select do |element_definition|
        element_definition[:types]&.include?("Reference")
      end
    end

    def must_support_references_with_target_profile
      # mapping array of target_profiles to array of {path, target_profile} pair
      must_support_references.map do |element_definition|
        (element_definition[:target_profiles] || [""]).map do |target_profile|
          {
            path: element_definition[:path],
            target_profile:
          }
        end
      end.flatten
    end

    # Memoised in full, including the choice filtering below. The filter's
    # predicate reads the collection it is mutating, so running it again on an
    # already filtered collection can remove further entries. Callers read this
    # more than once per test, so it has to settle on the first call.
    def unresolved_references(resources = [], rewrite_profile_url = {}, readable_resource_types = [])
      @unresolved_references ||= begin
        unresolved =
          must_support_references_with_target_profile.select do |reference_path_profile_pair|
            path = reference_path_profile_pair[:path]
            target_profile = reference_path_profile_pair[:target_profile]

            found_one_reference = false

            resolve_one_reference = resources.any? do |resource|
              value_found = resolve_path(resource, path, metadata:)
              next if value_found.empty?

              resolvable = if readable_resource_types.present?
                             value_found.select { |ref| readable_resource_types.include?(ref.resource_type) }
                           else
                             value_found
                           end

              next if resolvable.empty?

              found_one_reference = true

              resolvable.any? do |reference|
                validate_reference_resolution(resource, reference, target_profile, rewrite_profile_url, path:)
              end
            end

            found_one_reference && !resolve_one_reference
          end

        if metadata.must_supports[:choices].present?
          unresolved.delete_if do |reference|
            choice_profiles = metadata.must_supports[:choices].find do |choice|
              choice[:target_profiles]&.include?(reference[:target_profile])
            end

            choice_profiles.present? &&
              choice_profiles[:target_profiles]&.any? do |profile|
                unresolved.none? do |element|
                  element[:target_profile] == profile
                end
              end
          end
        end

        unresolved
      end
    end

    def validate_reference_resolution(resource, reference, target_profile, rewrite_profile_url, path: nil)
      return true if is_reference_resolved?(reference, target_profile)

      if reference.contained?
        # if reference_id is blank it is referring to itself, so we know it exists
        return true if reference.reference_id.blank?

        contained = Array(resource.contained).select { |candidate| candidate&.id == reference.reference_id }

        # Nothing with that id means the reference is unresolvable. Something
        # with that id that fails validation is the same finding as a
        # non-conformant external target, so it is recorded the same way.
        return false if contained.empty?

        conforms = contained.any? do |contained_resource|
          resource_is_valid_with_target_profile?(contained_resource, target_profile, rewrite_profile_url)
        end
        return true if conforms

        record_nonconformant_reference_target(path, reference, target_profile)
        return false
      end

      reference_type = reference.resource_type
      reference_id = reference.reference_id

      resolved_resource =
        begin
          if reference.relative?
            begin
              reference.resource_class
            rescue NameError
              return false
            end

            fhir_read(reference_type, reference_id)&.resource
          elsif reference.base_uri.chomp("/") == fhir_client.instance_variable_get(:@base_service_url).chomp("/")
            fhir_read(reference_type, reference_id)&.resource
          else
            get(reference.reference)&.resource
          end
        rescue StandardError => e
          Inferno::Application["logger"].error("Unable to resolve reference #{reference.reference}")
          Inferno::Application["logger"].error(e.full_message)
          return false
        end

      return false unless resolved_resource&.resourceType == reference_type && resolved_resource&.id == reference_id

      unless resource_is_valid_with_target_profile?(resolved_resource, target_profile, rewrite_profile_url)
        # The read succeeded, so the reference is reachable. The target simply
        # does not conform. Remember that so the caller can report it as a
        # finding rather than as missing data.
        record_nonconformant_reference_target(path, reference, target_profile)
        return false
      end

      record_resolved_reference(reference, target_profile)
      true
    end

    def get_target_profile_with_version(target_profile, rewrite_profile_url)
      if rewrite_profile_url.key?(target_profile)
        rewrite_profile_url[target_profile]
      else
        "#{target_profile}|#{metadata.profile_version}"
      end
    end

    def resource_is_valid_with_target_profile?(resource, target_profile, rewrite_profile_url)
      return true if target_profile.blank?

      validator = find_validator(:default)

      target_profile_with_version = get_target_profile_with_version(target_profile, rewrite_profile_url)
      begin
        # add_messages_to_runnable is false because we only need to know if the resource is valid;
        # logging every failed reference target as an error would be noisy.
        validator.resource_is_valid?(resource, target_profile_with_version, self, add_messages_to_runnable: false)
      rescue StandardError => e
        error_message = "Can't validate resource #{resource.resourceType} with profile #{target_profile}. Got error #{e.message}"

        assert false, error_message
      end
    end
  end
end
