# frozen_string_literal: true

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # The shown trace entries grouped by the questionnaire they come from, in the
    # order first seen, each with the title a section shows for it.
    class Forms
      include Enumerable

      def initialize(entries)
        @forms = entries.select(&:shown?).group_by(&:form_key)
      end

      def empty?
        @forms.empty?
      end

      # Yields each form's title and entries.
      def each
        @forms.each_value { |entries| yield title(entries.first), entries }
      end

      # The title, or the URL or id for an untitled form, with the version when
      # another form here has the same title, as an assembled modular form does.
      def title(entry)
        title = entry.form_title
        version = entry.form_version
        same_title = @forms.values.count { |entries| entries.first.form_title == title }
        same_title > 1 && version ? "#{title}, version #{version}" : title
      end
    end
  end
end
