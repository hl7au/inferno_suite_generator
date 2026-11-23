# frozen_string_literal: true

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # A shown source in one group it fits, and the test that lists it there (nil when none does).
    Placement = Struct.new(:source, :group, :test) do
      # The group whose test lists the source.
      def owner = group

      def listed_in?(other) = test && owner.equal?(other)

      def test_label = test[:kind]

      def intro = format(Markdown::INTROS.fetch(test[:kind]), resource: group.resource)

      def reads
        source.uses.flat_map { |use| use.reads(source) }
      end
    end

    # One type of a root sdc-questionnaire-launchContext: the resource the form is opened for.
    class LaunchContext
      URL = "/sdc-questionnaire-launchContext"

      attr_reader :form, :name, :type

      # One source per type; none when the extension is not a launch context or has no name.
      def self.from(form, extension)
        parts = parts(extension)
        name = name_of(parts["name"]&.first)
        name ? types(parts).map { |type| new(form, name, type) } : []
      end

      def self.parts(extension)
        parts = extension["url"].to_s.end_with?(URL) ? QuestionnaireUsage.list(extension, "extension") : []
        parts.group_by { |part| part["url"] }
      end

      def self.types(parts) = [*parts["type"]].filter_map { |part| QuestionnaireUsage.text(part, "valueCode") }

      def self.name_of(part)
        QuestionnaireUsage.text(part, "valueCoding", "code") || QuestionnaireUsage.text(part, "valueId")
      end

      def initialize(form, name, type)
        @form = form
        @name = name
        @type = type
      end

      def uses
        @uses ||= form.uses(name) { |chain| chain.paths_for(type) }
      end

      def shown? = uses.any?

      def fits(groups)
        groups.select { |group| group.resource == type }
      end

      def placement(group)
        Placement.new(self, group, group.find_test("read"))
      end

      def heading = "**Launch context #{name}**: the #{type} the form is opened for"

      def context = "#{form.title} launch context #{name}"
    end
  end
end
