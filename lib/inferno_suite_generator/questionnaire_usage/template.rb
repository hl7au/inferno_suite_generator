# frozen_string_literal: true

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # One sdc-questionnaire-templateExtract on the root or an item whose template reference (#id) names a
    # contained resource. Always shown; a template on an item is used by that item.
    class Template
      URL = "/sdc-questionnaire-templateExtract"
      PATCH_URL = "/TemplateExtractExtensionPatchRequestUrl"

      # Where a templateExtract sits: its form, the form's contained resources by #id, its item (nil on the root).
      Site = Struct.new(:form, :contained, :item) do
        def context(ref)
          [form.title, "templateExtract", ref, "on", QuestionnaireUsage.node_label(item ? item["linkId"] : :root)]
            .compact.join(" ")
        end
      end

      # The templates on the root, then on every item, in document order.
      def self.all(form, data)
        resources = contained(data)
        [nil, *items(data)].flat_map { |item| at(Site.new(form, resources, item), item || data) }
      end

      def self.at(site, node) = QuestionnaireUsage.list(node, "extension").filter_map { |ext| from(site, ext) }

      # The contained resources by #id; one without an id cannot be referenced.
      def self.contained(data)
        QuestionnaireUsage.list(data, "contained").filter_map do |resource|
          id = QuestionnaireUsage.text(resource, "id")
          ["##{id}", resource] if id
        end.to_h
      end

      def self.items(node) = QuestionnaireUsage.list(node, "item").flat_map { |item| [item, *items(item)] }

      def self.from(site, extension)
        return unless extension["url"].to_s.end_with?(URL)

        parts = QuestionnaireUsage.list(extension, "extension")
        ref = reference(parts)
        ref ? build(site, ref, parts) : skip(site.context(nil), "no template reference")
      end

      def self.reference(parts)
        QuestionnaireUsage.text(parts.find { |part| part["url"] == "template" }, "valueReference", "reference")
      end

      # A PatchRequestUrl sub-extension makes it a FHIRPath Patch.
      def self.build(site, ref, parts)
        return skip(site.context(ref), "no contained resource #{ref}") unless site.contained[ref]

        patch = parts.find { |part| part["url"].to_s.end_with?(PATCH_URL) }
        typed(patch ? PatchTemplate.new(site, ref, patch) : CreateTemplate.new(site, ref))
      end

      # A template without a type is skipped.
      def self.typed(template) = template.type ? template : skip(template.context, template.untyped)

      def self.skip(context, reason)
        QuestionnaireUsage.log("skipping #{context}: #{reason}")
        nil
      end

      def initialize(site, ref)
        @site = site
        @ref = ref
        @resource = site.contained[ref]
      end

      def form = @site.form

      def id = @resource["id"]

      def shown? = true

      def context = @site.context(@ref)

      def details(_group) = []

      def unused_lines = ["Its answers come from the whole form"]

      def uses
        item = @site.item
        @uses ||= item ? [Use.new(Form.label(item)).tap { |use| use.add(Form.action(URL), []) }] : []
      end

      private

      attr_reader :resource
    end

    # A template that creates the contained resource. Matched by its code and category codings too.
    class CreateTemplate < Template
      def type = QuestionnaireUsage.text(resource, "resourceType")

      def untyped = "the contained resource has no resourceType"

      def codes
        @codes ||= Codes.from_resource(resource)
      end

      def heading
        coded = [*codes["code"]].map { |code| code.compact.join("|") }
        "**Extraction template #{id}**: creates a new #{type}#{" with code #{coded.join(", ")}" if coded.any?} " \
          "from the answers"
      end

      def placement(group, _groups) = Placement.new(self, group, group.find_test("create"))
    end

    # A FHIRPath Patch Parameters template. Fixes no codes, so it is matched by type only.
    class PatchTemplate < Template
      REQUEST_TYPE = %r{\A'(\w+)/}

      def initialize(site, ref, part)
        super(site, ref)
        @request_url = QuestionnaireUsage.text(part, "valueString")
      end

      # The first segment of the first operation's path, else a leading 'Type/ in the request URL.
      def type
        @type ||= [path_type, @request_url.to_s[REQUEST_TYPE, 1]].find { |name| FHIR::RESOURCES.include?(name) }
      end

      def untyped = "no resource type in its patch path or request URL"

      def codes = nil

      def heading = "**Extraction template #{id}**: updates an existing #{type} with a FHIRPath Patch"

      # An update test that creates a resource is never used.
      # :reek:FeatureEnvy
      def placement(group, _groups)
        Placement.new(self, group, group.find_test("patch") || group.find_test("update", option: "update"))
      end

      private

      def path_type
        operation = QuestionnaireUsage.list(resource, "parameter").find { |param| param["name"] == "operation" }
        path = QuestionnaireUsage.list(operation, "part").find { |part| part["name"] == "path" }
        QuestionnaireUsage.text(path, "valueString").to_s.split(".").first
      end
    end
  end
end
