# frozen_string_literal: true

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # The element paths a group's tests check.
    class CheckedElements
      ALWAYS_PRESENT = %w[id].freeze
      EXTENSION_URL = /\A((?:modifierE|e)xtension)\[url=(.+)\]\z/
      EXTENSION_SLICE = /\A(?:modifierE|e)xtension:/
      EXTENSION_REQUIRED = /\A(?:extension\[url=value\](?:\.value(?:[A-Z]\w*)?)?|value(?:[A-Z]\w*)?)?\z/

      def initialize(group)
        must_supports = group.must_supports || {}
        paths = element_paths(must_supports, group.mandatory_elements.to_a)
        @paths = paths.to_set { |path| plain(path) }
        @choices = choice_paths(paths)
        @slices = must_supports[:extensions].to_a.to_h { |extension| slice(extension) }
      end

      def label(path)
        sliced(path).gsub(%r{\[url=(?:[^\]]*/)?([^\]/]+)\]}, '[\1]')
      end

      def checked?(path)
        name = sliced(path)
        ALWAYS_PRESENT.include?(name) || @paths.include?(without_choice_types(name)) || required_by_extension?(name)
      end

      private

      def required_by_extension?(name)
        steps = segments(name)
        slice = steps.rindex { |segment| segment.match?(EXTENSION_SLICE) }
        slice && steps.drop(slice + 1).join(".").match?(EXTENSION_REQUIRED)
      end

      def sliced(path)
        segments(path).each_with_object([]) do |segment, done|
          _, member, url = segment.match(EXTENSION_URL).to_a
          done << (@slices[[done.join("."), member, url]] || segment)
        end.join(".")
      end

      def element_paths(must_supports, mandatory)
        elements = must_supports[:elements].to_a + must_supports[:slices].to_a
        (elements.map { |element| element[:path] } + mandatory.map { |path| path.split(".", 2).last }).compact
      end

      def choice_paths(paths)
        paths.filter_map do |path|
          parent, _, name = plain(path[/\A.*?\[x\]/]).rpartition(".") if path.include?("[x]")
          [parent, name] if name
        end.to_set
      end

      def without_choice_types(name)
        segments(name).each_with_object([]) do |segment, done|
          done << (choice_name(done.join("."), segment) || segment)
        end.join(".")
      end

      def choice_name(parent, segment)
        @choices.find { |choice_parent, name| choice_parent == parent && segment.match?(/\A#{name}[A-Z]/) }&.last
      end

      def slice(extension)
        parent, _, segment = extension[:id].to_s.split(".", 2).last.to_s.rpartition(".")
        [[plain(parent), segment.split(":").first, extension[:url]], segment]
      end

      def plain(path)
        path.gsub("[x]", "").gsub(/:[^.]+/, "")
      end

      def segments(path)
        path.scan(/(?:[^.\[]+|\[[^\]]*\])+/)
      end
    end
  end
end
