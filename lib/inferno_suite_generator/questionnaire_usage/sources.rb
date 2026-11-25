# frozen_string_literal: true

require_relative "form"
require_relative "fhir_query"
require_relative "profile_matcher"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # One thing a questionnaire reads from the server or writes to it.
    class Source
      attr_reader :form, :name, :groups, :item_uses

      def initialize(form:, name:, groups:, item_uses: [])
        @form = form
        @name = name
        @groups = groups
        @item_uses = item_uses
      end

      def query; end

      def shown?
        item_uses.any?
      end

      def unused_line; end

      def lookups(_resource)
        []
      end

      def requesting(group, _groups)
        [group]
      end

      def search?
        false
      end
    end

    # A `launchContext` resource, like `%patient`.
    class LaunchContext < Source
      URL = "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-launchContext"

      def self.in(form, matcher, _ig_resources)
        form.extensions(form.root, URL).flat_map do |extension|
          parts = Form.list(extension["extension"])
          name_part = parts.find { |part| part["url"] == "name" } || {}
          name = name_part.dig("valueCoding", "code") || name_part["valueId"]
          types = parts.select { |part| part["url"] == "type" }.filter_map { |part| part["valueCode"] }
          name ? types.filter_map { |type| of(form, name, type, matcher) } : []
        end
      end

      def self.of(form, name, type, matcher)
        groups = matcher.match(type, any_of_type: true, context: "#{form.label} launch context #{name}")
        return unless groups

        item_uses = form.uses(name, form.root, Origin.resource) { |chain_type| [nil, type].include?(chain_type) }
        new(form:, name:, groups:, item_uses:)
      end

      def lookups(_resource)
        [["read", {}]]
      end

      def heading(resource)
        "**Launch context #{name}**: the #{resource} the form is opened for"
      end
    end

    # An x-fhir-query `variable`: a search, or a read by id.
    class Query < Source
      attr_reader :query

      def self.in(form, matcher, ig_resources)
        form.variables(Form::QUERY).flat_map do |name, text, node|
          query = FhirQuery.new(text)
          label = "#{form.label} query #{name}"
          groups = matcher.match(query.resource_type, codes: query.codes, any_of_type: query.read?, context: label)
          targets = Include.targets(query, label, ig_resources) { form.types(name, node) }
          uses = lambda do |&accept|
            form.uses(name, node, query.read? ? Origin.resource : Origin.bundle, &accept)
          end
          others = targets.map(&:last) - [query.resource_type]
          own = new(form:, name:, query:, groups:, item_uses: uses.call { |type| !others.include?(type) }) if groups
          [own, *Include.of(targets, matcher, label, uses, form:, name:, query:)].compact
        end
      end

      def initialize(query:, **source)
        super(**source)
        @query = query
      end

      def shown?
        super || query.includes.any?
      end

      def unused_line
        "No item reads its results; it fetches #{query.includes.join(", ")} through _include"
      end

      def lookups(_resource)
        return [["read", {}]] if query.read?

        search? ? [["search", { search_names: query.search_params }]] : []
      end

      def search?
        !query.read? && query.search_params.any?
      end

      def heading(resource)
        action = query.read? ? "reads one #{resource} by id" : "searches #{resource} resources"
        "**Query #{name}**: #{action}"
      end
    end

    # What a query fetches through one `_include` target type.
    class Include < Source
      attr_reader :query

      def self.targets(query, label, ig_resources)
        type = query.resource_type
        query.other_includes.each do |param, value|
          QuestionnaireUsage.log("skipping #{param}=#{value} in #{label}: only _include of #{type} is traced")
        end
        query.includes.flat_map do |value|
          source, param, explicit = value.split(":", 3)
          targets = explicit ? [explicit] : Array(ig_resources.search_param_by_resource_and_code(source, param)&.target)
          targets = yield - [type] if targets.empty?
          QuestionnaireUsage.log("unresolved #{label} include #{value}: no target type") if targets.empty?
          targets.map { |target| [value, target] }
        end
      end

      def self.of(targets, matcher, label, uses, **source)
        targets.filter_map do |value, target|
          groups = matcher.match(target, any_of_type: true, context: "#{label} include #{value}")
          next unless groups

          own_type = target == source[:query].resource_type
          new(**source, include: value, groups:, item_uses: own_type ? [] : uses.call { |type| type == target })
        end
      end

      def initialize(query:, include:, **source)
        super(**source)
        @query = query
        @include = include
      end

      def lookups(resource)
        [["include", { search_names: query.search_params, include_targets: [resource] }],
         ["include", { include_targets: [resource] }]]
      end

      def requesting(_group, groups)
        groups.select { |group| group.resource == query.resource_type }
      end

      def heading(resource)
        "**Query #{name}**: fetches #{resource} resources through _include=#{@include}"
      end
    end

    # A contained resource a `templateExtract` fills from the answers.
    class Template < Source
      URL = "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-templateExtract"
      PATCH_URL_SUFFIX = "/TemplateExtractExtensionPatchRequestUrl"

      def self.in(form, matcher, _ig_resources)
        form.nodes.flat_map do |node|
          form.extensions(node, URL).filter_map do |extension|
            parts = Form.list(extension["extension"])
            reference = parts.find { |part| part["url"] == "template" }&.dig("valueReference", "reference").to_s
            patch_url = parts.find { |part| part["url"].to_s.end_with?(PATCH_URL_SUFFIX) }&.dig("valueString")
            of(form, node, reference, patch_url, matcher)
          end
        end
      end

      def self.of(form, node, reference, patch_url, matcher)
        on_root = form.root?(node)
        label = "#{form.label} templateExtract #{reference} on #{on_root ? "root" : node["linkId"]}"
        template = form.contained(reference.delete_prefix("#"))
        return QuestionnaireUsage.log("skipping #{label}: no contained resource #{reference}") unless template

        patch = !patch_url.nil?
        codes = patch ? {} : ProfileMatcher::Codes.from_template(template)
        type = patch ? patch_target(template, patch_url) : template["resourceType"]
        groups = matcher.match(type, codes:, context: label)
        return unless groups

        new(form:, name: template["id"], groups:, patch:,
            codes: codes.fetch(:code) { [] }.map { |coding| coding.values_at(:system, :code).compact.join("|") },
            item_uses: on_root ? [] : [ItemUse.of(node, "templateExtract")])
      end

      def self.patch_target(template, patch_url)
        paths = template["parameter"].to_a.flat_map { |parameter| parameter["part"].to_a }
                                     .filter_map { |part| part["valueString"] if part["name"] == "path" }
        paths.first&.split(".")&.first || patch_url[%r{\A\s*'([A-Za-z]+)/}, 1]
      end

      def initialize(patch:, codes: [], **source)
        super(**source)
        @patch = patch
        @codes = codes
      end

      def shown?
        true
      end

      def unused_line
        "Its answers come from the whole form"
      end

      def lookups(_resource)
        @patch ? [["patch", {}], ["update", { option: "update" }]] : [["create", {}]]
      end

      def heading(resource)
        return "**Extraction template #{name}**: updates an existing #{resource} with a FHIRPath Patch" if @patch

        codes = " with code #{@codes.join(", ")}" unless @codes.empty?
        "**Extraction template #{name}**: creates a new #{resource}#{codes} from the answers"
      end
    end
  end
end
