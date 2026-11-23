# frozen_string_literal: true

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # The element paths one group's profile checks: Must Support elements and slices, mandatory
    # elements, id, and Must Support extension slices. [x] and slice names are ignored.
    class CheckedElements
      EXTENSION_TAIL = '(?:(?:\.extension\[url=[^\]]*\])?\.value(?:[A-Z]\w*)?)?'

      def self.plain(path) = path.gsub("[x]", "").gsub(/:[^.]+/, "")

      def self.declared(supports, group)
        prefix = "#{group.resource}."
        [*supports[:elements], *supports[:slices]].map { |element| element[:path] } +
          [*group.mandatory_elements].map { |path| path.delete_prefix(prefix) }
      end

      # The slice itself, its value[x], or a sub-extension's value[x].
      def self.extension_pattern(extension, resource)
        slice = "#{plain(extension[:id].delete_prefix("#{resource}."))}[url=#{extension[:url]}]"
        /\A#{Regexp.escape(slice)}#{EXTENSION_TAIL}\z/
      end

      def initialize(group)
        supports = group.must_supports || {}
        paths = CheckedElements.declared(supports, group)
        @choices = paths.grep(/\[x\]/).map { |path| CheckedElements.plain(path[/\A.*?\[x\]/]) }
        @paths = Set.new(paths.map { |path| CheckedElements.plain(path) }) << "id"
        @extensions = [*supports[:extensions]].map do |extension|
          CheckedElements.extension_pattern(extension, group.resource)
        end
      end

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
