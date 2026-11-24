# frozen_string_literal: true

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # code and category values as { param => [[system or nil, code], …] }, only for params with values.
    module Codes
      PARAMS = %w[code category].freeze
      CONCEPTS = %w[patternCodeableConcept fixedCodeableConcept].freeze
      CODINGS = %w[patternCoding fixedCoding].freeze

      # A comma means OR; a value with a {{…}} template is ignored.
      def self.from_query(params)
        params.select { |name, value| PARAMS.include?(name) && !value.include?("{{") }
              .flat_map { |name, value| value.split(",").map { |token| [name, coding(token)] } }
              .group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
      end

      # system|code, |code or code.
      def self.coding(token)
        system, code = token.include?("|") ? token.split("|", 2) : [nil, token]
        [system.to_s.empty? ? nil : system, code]
      end

      # The codes a profile snapshot fixes under <Type>.code and <Type>.category.
      def self.from_profile(profile, type)
        hash = profile&.to_hash
        elements = QuestionnaireUsage.list(QuestionnaireUsage.dig(hash, ["snapshot"]), "element")
        by_id = elements.to_h { |element| [element["id"], element] }
        PARAMS.to_h { |param| [param, elements.flat_map { |element| fixed(element, "#{type}.#{param}", by_id) }] }
              .reject { |_param, codes| codes.empty? }
      end

      def self.fixed(element, base, by_id)
        case element["path"]
        when base, "#{base}.coding" then concept_codes(element)
        when "#{base}.coding.code" then slice_code(element, by_id)
        else []
        end
      end

      def self.concept_codes(element)
        codings = CONCEPTS.flat_map { |key| QuestionnaireUsage.list(element[key], "coding") } +
                  CODINGS.filter_map { |key| element[key] }.grep(Hash)
        codings.filter_map { |coding| [coding["system"], coding["code"]] if coding["code"] }
      end

      # fixedCode/patternCode on a coding.code slice element, with its sibling system's fixedUri/patternUri.
      def self.slice_code(element, by_id)
        code = element["fixedCode"] || element["patternCode"]
        sibling = by_id[element["id"].to_s.sub(/\.code\z/, ".system")] || {}
        code ? [[sibling["fixedUri"] || sibling["patternUri"], code]] : []
      end

      def self.same?(one, other)
        (one_system, one_code), (other_system, other_code) = one, other
        one_code == other_code && (one_system.nil? || other_system.nil? || one_system == other_system)
      end

      def self.overlap?(source, fixed, param)
        source[param].any? { |code| fixed[param].any? { |other| same?(code, other) } }
      end

      def self.shared(source, fixed) = source.keys & fixed.keys

      # A shared parameter with a common code.
      def self.matches?(source, fixed) = shared(source, fixed).any? { |param| overlap?(source, fixed, param) }

      # code=system|code,code, category=… or (no codes).
      def self.text(codes)
        return "(no codes)" if codes.empty?

        codes.map { |param, list| "#{param}=#{list.map { |code| code.compact.join("|") }.join(",")}" }.join(", ")
      end
    end

    # Matches a source to the groups of its type, by the code and category their profiles fix (§3.6).
    # Each profile's fixed codes are read once.
    class Matcher
      def initialize(ig_resources)
        @ig_resources = ig_resources
        @fixed = Hash.new { |cache, group| cache[group] = fixed(group) }.compare_by_identity
      end

      # The groups of the source's type it fits; a source without codes fits them all.
      def fits(source, groups)
        codes = source.codes
        return groups unless codes && groups.any?

        groups.one? ? only(source, codes, groups) : several(source, codes, groups)
      end

      private

      def fixed(group) = Codes.from_profile(@ig_resources.profile_by_url(group.profile_url), group.resource)

      # One group fits unless a parameter both give has no common code.
      def only(source, codes, groups)
        fixed = @fixed[groups.first]
        return groups if Codes.shared(codes, fixed).empty? || Codes.matches?(codes, fixed)

        unresolved(source, "the #{source.type} profile fixes #{Codes.text(fixed)}, not #{Codes.text(codes)}")
      end

      def several(source, codes, groups)
        matching = groups.select { |group| Codes.matches?(codes, @fixed[group]) }
        return unresolved(source, "no #{source.type} profile matches #{Codes.text(codes)}") if matching.empty?

        if matching.size > 1
          QuestionnaireUsage.log("#{source.context} matches several profiles: #{matching.map(&:profile_url).join(", ")}")
        end
        matching
      end

      def unresolved(source, reason)
        QuestionnaireUsage.log("unresolved #{source.context}: #{reason}")
        []
      end
    end
  end
end
