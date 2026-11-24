# frozen_string_literal: true

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # code and category values as { param => [[system or nil, code], …] }, only for params with values.
    module Codes
      PARAMS = %w[code category].freeze
      CONCEPTS = %w[patternCodeableConcept fixedCodeableConcept].freeze
      CODINGS = %w[patternCoding fixedCoding].freeze

      # Only code= and category= without a modifier; a comma means OR; a value with a {{…}} template is ignored.
      def self.from_query(params)
        params.select { |name, value| PARAMS.include?(name) && !value.include?("{{") }
              .flat_map { |name, value| tokens(name, value) }
              .group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
      end

      # A token without a code (system|) is ignored.
      def self.tokens(name, value)
        value.split(",").map { |token| [name, coding(token)] }.reject { |_name, code| code.last.to_s.empty? }
      end

      # system|code, |code or code.
      def self.coding(token)
        system, code = token.include?("|") ? token.split("|", 2) : [nil, token]
        [system.to_s.empty? ? nil : system, code]
      end

      # The codes a profile's snapshot fixes under <Type>.code and <Type>.category ({} without a profile).
      def self.from_profile(profile)
        hash = profile ? profile.to_hash : {}
        PARAMS.to_h { |param| [param, param_codes(hash, param)] }.select { |_param, codes| codes.any? }
      end

      def self.param_codes(profile, param)
        elements = QuestionnaireUsage.list(profile["snapshot"], "element")
        base = "#{profile["type"]}.#{param}"
        elements.flat_map { |element| element_codes(element, base, elements) }
      end

      def self.element_codes(element, base, elements)
        case element["path"]
        when base, "#{base}.coding" then concept_codes(element)
        when "#{base}.coding.code" then slice_code(element, elements)
        else []
        end
      end

      # A create template's code.coding and category[].coding.
      def self.from_resource(resource)
        concepts = { "code" => [resource["code"]], "category" => QuestionnaireUsage.list(resource, "category") }
        concepts.transform_values { |list| pairs(list.flat_map { |concept| codings(concept) }) }
                .select { |_param, codes| codes.any? }
      end

      # pattern/fixed CodeableConcept and Coding.
      def self.concept_codes(element)
        pairs(element.values_at(*CONCEPTS).flat_map { |concept| codings(concept) } +
              element.values_at(*CODINGS).grep(Hash))
      end

      def self.codings(concept) = QuestionnaireUsage.list(concept, "coding")

      def self.pairs(codings) = codings.map { |coding| coding.values_at("system", "code") }.select(&:last)

      # fixedCode/patternCode on a coding.code slice element, with its sibling system's fixedUri/patternUri.
      def self.slice_code(element, elements)
        code = element["fixedCode"] || element["patternCode"]
        code ? [[sibling_system(element, elements), code]] : []
      end

      def self.sibling_system(element, elements)
        system_id = element["id"].to_s.sub(/\.code\z/, ".system")
        sibling = elements.find { |other| other["id"] == system_id } || {}
        sibling["fixedUri"] || sibling["patternUri"]
      end

      # Equal codes, and equal systems unless either is missing.
      def self.same?(one, other)
        one.last == other.last && [one.first, other.first].compact.uniq.size < 2
      end

      def self.overlap?(codes, others) = codes.product(others).any? { |pair| same?(*pair) }

      def self.shared(source, fixed) = source.keys & fixed.keys

      # A parameter both give with a common code.
      def self.matches?(source, fixed)
        shared(source, fixed).any? { |param| overlap?(source[param], fixed[param]) }
      end

      # code=system|code,code, category=… or (no codes).
      def self.text(codes)
        return "(no codes)" if codes.empty?

        codes.map { |param, list| "#{param}=#{list_text(list)}" }.join(", ")
      end

      def self.list_text(list) = list.map { |code| code.compact.join("|") }.join(",")
    end

    # Matches a source to the groups of its type by the code and category their profiles fix (§3.6), for
    # search queries and create templates. Each profile's fixed codes are read once.
    class Matcher
      def self.of_type(source, groups)
        type = source.type
        typed = groups.select { |group| group.resource == type }
        QuestionnaireUsage.log("untraced #{source.context}: no group for #{type}") if typed.empty?
        typed
      end

      def self.unresolved(source, reason)
        QuestionnaireUsage.log("unresolved #{source.context}: #{reason}")
        []
      end

      # Several matching profiles are all kept.
      def self.pick(source, codes, matching)
        return unresolved(source, "no #{source.type} profile matches #{Codes.text(codes)}") if matching.empty?

        urls = matching.map(&:profile_url)
        QuestionnaireUsage.log("#{source.context} matches several profiles: #{urls.join(", ")}") if urls.size > 1
        matching
      end

      def initialize(ig_resources)
        @fixed = Hash.new { |cache, url| cache[url] = Codes.from_profile(ig_resources.profile_by_url(url)) }
      end

      # The groups the source fits: those of its type, by codes too when the source has them.
      def fits(source, groups)
        typed = Matcher.of_type(source, groups)
        codes = source.codes
        codes && typed.any? ? by_codes(source, codes, typed) : typed
      end

      private

      def fixed(group) = @fixed[group.profile_url]

      def by_codes(source, codes, groups)
        first, *rest = groups
        rest.empty? ? only(source, codes, first) : Matcher.pick(source, codes, matching(codes, groups))
      end

      def matching(codes, groups) = groups.select { |group| Codes.matches?(codes, fixed(group)) }

      # The only group fits unless a parameter both give has no common code.
      def only(source, codes, group)
        fixed = fixed(group)
        return [group] if Codes.shared(codes, fixed).all? { |param| Codes.overlap?(codes[param], fixed[param]) }

        Matcher.unresolved(source, "the #{source.type} profile fixes #{Codes.text(fixed)}, not #{Codes.text(codes)}")
      end
    end
  end
end
