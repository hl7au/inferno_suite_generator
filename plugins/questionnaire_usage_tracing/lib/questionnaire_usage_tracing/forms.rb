# frozen_string_literal: true

module InfernoSuitePlugins
  module QuestionnaireUsageTracing
    # Trace entries grouped by the questionnaire they come from, in the order
    # first seen, each with the title a section shows for it.
    class Forms
      include Enumerable

      def self.key(entry)
        entry.values_at(:questionnaire_url, :questionnaire_id, :questionnaire_version)
      end

      def initialize(entries)
        @forms = entries.group_by { |entry| self.class.key(entry) }
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
        title = title_of(entry)
        version = entry[:questionnaire_version]
        same_title = @forms.values.count { |entries| title_of(entries.first) == title }
        same_title > 1 && version ? "#{title}, version #{version}" : title
      end

      private

      # :reek:UtilityFunction
      def title_of(entry)
        entry[:questionnaire_title] || entry[:questionnaire_url] || entry[:questionnaire_id] || "Untitled questionnaire"
      end
    end
  end
end
