# frozen_string_literal: true

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # The element paths one group's profile checks: Must Support elements and slices, mandatory
    # elements, id, and Must Support extension slices. [x] and slice names are ignored.
    class CheckedElements
      EXTENSION = /(?<=modifierExtension|extension)\[url=([^\]]*)\]/
      URL = /\[url=[^\]]*\]/
      EXTENSION_TAIL = '(?:(?:\.extension\[url=value\])?\.value(?:[A-Z]\w*)?)?'

      def self.plain(path) = path.gsub("[x]", "").gsub(/:[^.]+/, "")

      def self.declared(supports, group)
        prefix = "#{group.resource}."
        [*supports[:elements], *supports[:slices]].map { |element| element[:path] } +
          [*group.mandatory_elements].map { |path| path.delete_prefix(prefix) }
      end

      # The path an extension slice is read by, such as extension[url=<url>].
      def self.slice_path(extension, resource)
        "#{plain(extension[:id].delete_prefix("#{resource}."))}[url=#{extension[:url]}]"
      end

      # { slice path => slice name } of the profile's Must Support extensions.
      def self.slices(supports, resource)
        [*supports[:extensions]].to_h { |extension| [slice_path(extension, resource), extension[:id].split(":").last] }
      end

      # The path with each extension shown by its slice name in { slice path => slice name }, else by its
      # URL's last segment: extension:race or extension[individual-pronouns].
      def self.label(path, slices)
        path.gsub(EXTENSION) do
          match = Regexp.last_match
          slice = slices["#{match.pre_match.gsub(URL, "")}#{match}"]
          slice ? ":#{slice}" : "[#{match[1].split("/").last}]"
        end
      end

      # The slice itself, its value[x], or its extension[url=value].value[x].
      def self.extension_pattern(slice_path) = /\A#{Regexp.escape(slice_path)}#{EXTENSION_TAIL}\z/

      def self.choices(paths) = paths.grep(/\[x\]/).map { |path| plain(path[/\A.*?\[x\]/]) }

      def initialize(group)
        supports = group.must_supports || {}
        paths = CheckedElements.declared(supports, group)
        @choices = CheckedElements.choices(paths)
        @paths = Set.new(paths.map { |path| CheckedElements.plain(path) }) << "id"
        @slices = CheckedElements.slices(supports, group.resource)
        @extensions = @slices.keys.map { |path| CheckedElements.extension_pattern(path) }
      end

      attr_reader :slices

      def checks?(path)
        @paths.include?(path) || @paths.include?(by_choice(path)) || @extensions.any? { |pattern| pattern.match?(path) }
      end

      private

      # valueQuantity counts as the choice element value.
      def by_choice(path)
        @choices.reduce(path) { |choice_path, base| choice_path.sub(/\A#{Regexp.escape(base)}[A-Z]\w*(?=\.|\z)/, base) }
      end
    end
  end
end
