# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "inferno_suite_generator"

module InfernoSuiteGenerator
  class GeneratorTestKindsTest < Minitest::Test
    G = InfernoSuiteGenerator::Generator
    IgMetadata = Struct.new(:ig_test_id_prefix, :ig_module_name_prefix)

    # Answers only what IncludeSearchTestGenerator#includes asks for.
    class FakeConfigKeeper
      INCLUDE = { "type" => "include", "names" => %w[_id], "param" => "Patient:general-practitioner",
                  "target_resource" => "Practitioner", "paths" => ["generalPractitioner"] }.freeze

      def extra_searches(_profile_url, _resource)
        [INCLUDE]
      end
    end

    ID_SEARCH = { names: %w[_id] }.freeze
    NAME_SEARCH = { names: %w[family birthdate] }.freeze
    CHAIN = { target: "Practitioner", chain: "name", expectation: "SHOULD" }.freeze

    def setup
      @previous_config_keeper = Registry.get(:config_keeper)
      Registry.register(:config_keeper, FakeConfigKeeper.new)
      @dir = Dir.mktmpdir
      @ig = IgMetadata.new("ig", "Ig")
      @group = G::GroupMetadata.new(
        resource: "Patient", reformatted_version: "v100", interactions: [], searches: [ID_SEARCH, NAME_SEARCH],
        search_definitions: { _id: { path: "id" }, family: { path: "name.family" }, birthdate: { path: "birthDate" } },
        must_supports: { elements: [{ path: "generalPractitioner", types: ["Reference"] }] }
      )
    end

    def teardown
      Registry.register(:config_keeper, @previous_config_keeper)
      FileUtils.remove_entry(@dir)
    end

    def generators
      or_context = G::MultipleOrSearchTestGenerator::GenerationContext.new(@dir, @ig)
      [G::ReadTestGenerator.new(@group, @dir, @ig), search_generator(NAME_SEARCH),
       G::MultipleAndSearchTestGenerator.new("family", @group, {}, @dir, @ig),
       G::MultipleOrSearchTestGenerator.new("family", @group, {}, or_context),
       G::ChainSearchTestGenerator.new("general-practitioner", @group, {}, @dir, CHAIN, @ig), include_generator,
       G::ProvenanceRevincludeSearchTestGenerator.new(@group, ID_SEARCH, @dir, @ig),
       G::ValidationTestGenerator.new(@group, @ig, base_output_dir: @dir),
       G::MustSupportTestGenerator.new(@group, @dir, @ig), G::ReferenceResolutionTestGenerator.new(@group, @dir, @ig),
       G::CreateTestGenerator.new(@group, @dir, @ig), *update_generators,
       G::PatchTestGenerator.new(@group, @dir, @ig, "FHIRPathJSON")]
    end

    def search_generator(search)
      G::SearchTestGenerator.new(@group, search, @dir, @ig)
    end

    def include_generator
      G::IncludeSearchTestGenerator.new(@group, ID_SEARCH, @dir, FakeConfigKeeper::INCLUDE, @ig)
    end

    def update_generators
      %w[UPDATE UPDATE_CREATE].map { |type| G::UpdateTestGenerator.new(@group, @dir, @ig, type) }
    end

    def generate(generator)
      generator.define_singleton_method(:output) { "" }
      generator.generate
      generator
    end

    def test_every_built_in_generator_records_its_kind
      recorded = generators.map { |generator| @group.test_kind(generate(generator).test_id)[:kind] }

      assert_equal %w[read search multiple_and_search multiple_or_search chain_search include
                      provenance_revinclude_search validation must_support reference_resolution create update
                      update patch], recorded
    end

    def test_search_test_records_search_names
      search = generate(search_generator(NAME_SEARCH))

      assert_equal({ kind: "search", search_names: %w[family birthdate] }, @group.test_kind(search.test_id))
      assert_equal search.test_id, @group.find_test("search", search_names: %w[birthdate family])[:id]
    end

    def test_find_search_skips_search_derived_kinds
      generate(G::MultipleAndSearchTestGenerator.new("family", @group, {}, @dir, @ig))

      assert_nil @group.find_test("search", search_names: %w[family])
    end

    def test_include_test_details
      assert_equal({ search_names: %w[_id], include_targets: %w[Practitioner] }, include_generator.test_details)
    end

    def test_provenance_revinclude_test_details
      assert_equal({ search_names: %w[_id] },
                   G::ProvenanceRevincludeSearchTestGenerator.new(@group, ID_SEARCH, @dir, @ig).test_details)
    end

    def test_update_test_details
      assert_equal([{ option: "update" }, { option: "update_new" }], update_generators.map(&:test_details))
    end

    def test_find_update_option_skips_update_create_test
      update, update_create = update_generators.reverse_each.map { |generator| generate(generator) }.reverse

      found = @group.find_test("update", option: "update")[:id]

      assert_equal update.test_id, found
      refute_equal update_create.test_id, found
    end

    def test_basic_generator_test_details_default_to_empty
      assert_empty G::ReadTestGenerator.new(@group, @dir, @ig).test_details
    end
  end
end
