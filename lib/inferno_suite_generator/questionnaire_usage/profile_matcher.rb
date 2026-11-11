# frozen_string_literal: true

require_relative "trace"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # Finds the suite groups whose profile a questionnaire source links to.
    class ProfileMatcher
      PARAMS = FhirQuery::CODE_PARAMS

      def initialize(groups, ig_resources)
        @groups = groups
        @ig_resources = ig_resources
        @profile_codes = {}
      end

      # The groups the source links to, or `nil` when untraced or unresolved; `context` names it in logs.
      # The only group of a type matches unless the source has a `code` or `category` its profile fixes otherwise.
      def match(resource_type, codes: {}, any_of_type: false, context: nil)
        label = context || resource_type
        candidates = @groups.select { |group| group.resource == resource_type }
        return log("untraced #{label}: no group for #{resource_type}") if candidates.empty?
        return candidates if any_of_type
        return match_by_code(candidates, codes, label) unless candidates.one?

        fixed = profile_codes(candidates.first)
        return candidates if agree?(fixed, codes)

        log("unresolved #{label}: the #{resource_type} profile fixes #{Codes.format(fixed)}, " \
            "not #{Codes.format(codes)}")
      end

      private

      # The `code` and `category` values the group's profile fixes.
      def profile_codes(group)
        @profile_codes[group.profile_url] ||= Codes.from_profile(@ig_resources.profile_by_url(group.profile_url))
      end

      def match_by_code(candidates, codes, label)
        matches = candidates.select { |group| agree?(profile_codes(group), codes, shared: true) }
        if matches.empty?
          return log("unresolved #{label}: no #{candidates.first.resource} profile matches #{Codes.format(codes)}")
        end

        log("#{label} matches several profiles: #{matches.map(&:profile_url).join(", ")}") if matches.size > 1
        matches
      end

      # Whether the codes overlap on every param both give values for; with `shared:`, at least one must.
      def agree?(profile, source, shared: false)
        params = PARAMS.select { |param| profile[param].any? && source[param].to_a.any? }
        (!shared || params.any?) && params.all? { |param| Codes.overlap?(profile[param], source[param]) }
      end

      def log(message)
        QuestionnaireUsage.log(message)
      end

      # Builds and compares `codes` Hashes.
      module Codes
        CONCEPT_PATTERNS = %w[patternCodeableConcept fixedCodeableConcept].freeze
        CODING_PATTERNS = %w[patternCoding fixedCoding].freeze

        module_function

        # A template's `code.coding` and `category[].coding`.
        def from_template(template)
          PARAMS.to_h { |param| [param, list(template[param.to_s]).flat_map { |concept| codings(concept) }] }
        end

        # The codes a profile's snapshot fixes under `<Type>.code` and `<Type>.category`.
        def from_profile(profile)
          elements = snapshot_elements(profile)
          by_id = elements.to_h { |element| [element["id"], element] }
          codes = empty
          elements.each do |element|
            key = param(element["path"].to_s.split(".")[1])
            codes[key].concat(element_codes(element, by_id)) if key
          end
          codes.transform_values(&:uniq)
        end

        def snapshot_elements(profile)
          profile&.to_hash&.dig("snapshot", "element") || []
        end

        def overlap?(profile_values, source_values)
          profile_values.any? { |fixed| source_values.any? { |value| same_code?(fixed, value) } }
        end

        def same_code?(fixed, value)
          return false unless value[:code] == fixed[:code]

          value[:system].nil? || fixed[:system].nil? || value[:system] == fixed[:system]
        end

        def format(codes)
          values = PARAMS.flat_map do |param|
            codes[param].to_a.map { |value| "#{param}=#{value.values.compact.join("|")}" }
          end
          values.empty? ? "(no codes)" : values.join(", ")
        end

        # Codes fixed on one element: a `pattern[x]`/`fixed[x]` CodeableConcept
        # or Coding, or `fixedCode` on a coding slice.
        def element_codes(element, by_id)
          CONCEPT_PATTERNS.flat_map { |key| codings(element[key]) } +
            CODING_PATTERNS.filter_map { |key| coding_value(element[key]) } +
            [slice_code(element, by_id)].compact
        end

        # `fixedCode` on `<Type>.code.coding:Slice.code`, with the `fixedUri` of
        # its sibling `system`.
        def slice_code(element, by_id)
          code = element["fixedCode"] || element["patternCode"]
          return unless code && element["path"].to_s.end_with?(".coding.code")

          system_element = by_id[element["id"].to_s.sub(/\.code\z/, ".system")] || {}
          { system: system_element["fixedUri"] || system_element["patternUri"], code: }
        end

        def codings(concept)
          list(concept.is_a?(Hash) ? concept["coding"] : nil).filter_map { |coding| coding_value(coding) }
        end

        def coding_value(coding)
          { system: coding["system"], code: coding["code"] } if coding.is_a?(Hash) && coding["code"]
        end

        def list(value)
          value.is_a?(Array) ? value : [value].compact
        end

        def param(name)
          PARAMS.find { |known| known.to_s == name }
        end

        def empty
          PARAMS.to_h { |param| [param, []] }
        end
      end
    end
  end
end
