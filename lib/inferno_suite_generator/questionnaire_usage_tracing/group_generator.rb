# frozen_string_literal: true

require_relative "../generators/group_generator"

module InfernoSuiteGenerator
  module QuestionnaireUsageTracing
    # A `GroupGenerator` that adds a "Used in questionnaires" section to the
    # description of each group with a trace.
    class QuestionnaireAwareGroupGenerator < Generator::GroupGenerator
      class << self
        # `{ profile_url => [trace entries] }`, set before `generate` is called.
        attr_writer :traces

        def traces
          @traces || {}
        end
      end

      def description
        entries = self.class.traces[profile_url].to_a
        return super if entries.empty?

        "#{super}\n#{UsageSection.new(entries)}"
      end
    end

    # The "Used in questionnaires" Markdown for one group's trace entries, one
    # `###` heading per questionnaire. It shows only titles, names, queries,
    # paths, and item linkIds and texts, never FHIRPath expressions.
    #
    # The group template puts the description inside a Ruby `%( ... )`
    # literal, so `to_s` escapes `\`, `(`, `)` and `#{`, `#@`, `#$`.
    class UsageSection
      MAX_ITEMS = 10

      def initialize(entries)
        @entries = entries
      end

      def to_s
        lines = ["## Used in questionnaires"]
        @entries.group_by { |entry| entry[:questionnaire_title] || entry[:questionnaire_url] }.each do |title, entries|
          lines.push("", "### #{title}", "", *entries.flat_map { |entry| entry_lines(entry) })
        end
        escape("#{lines.join("\n")}\n")
      end

      private

      def entry_lines(entry)
        [heading(entry), reads(entry), items(entry)].compact
      end

      def heading(entry)
        case entry[:source]
        when "query" then "* Query `#{entry[:name]}`: `#{entry[:query]}`"
        when "include" then "* Included by query `#{entry[:name]}` through `#{entry[:include]}`"
        when "launch_context" then "* Launch context `#{entry[:name]}`"
        when "template_extract" then "* Extraction template `#{entry[:name]}` (#{entry[:patch] ? "patch" : "create"})"
        end
      end

      def reads(entry)
        paths = entry[:elements_read].to_a
        "  * Reads: #{paths.map { |path| "`#{path}`" }.join(", ")}" unless paths.empty?
      end

      # Up to `MAX_ITEMS` items, else only their count. An item that uses the
      # source in several extensions is shown once.
      def items(entry)
        usages = entry[:used_in].to_a.uniq { |usage| usage[:link_id] }
        return if usages.empty?
        return "  * Items: #{usages.size} items" if usages.size > MAX_ITEMS

        "  * Items: #{usages.map { |usage| item_label(usage) }.join(", ")}"
      end

      def item_label(usage)
        ["`#{usage[:link_id]}`", usage[:text].to_s.split.join(" ")].reject(&:empty?).join(" ")
      end

      def escape(text)
        text.gsub(/[\\()]|#[{@$]/) { |match| "\\#{match}" }
      end
    end
  end
end
