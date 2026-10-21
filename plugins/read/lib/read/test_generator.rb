# frozen_string_literal: true

module InfernoSuitePlugins
  module Read
    # Renders templates/read.rb.erb for one group. Class names, test ids and the test's place in the group
    # match the built-in ReadTestGenerator, so suites keep the same tests in the same order.
    class TestGenerator < InfernoSuiteGenerator::Plugins::TestGenerator
      self.template_name = "read.rb.erb"
      self.class_name_suffix = "ReadTest"
      self.test_id_suffix = "read_test"

      # Search, multiple OR / AND, chained and custom search tests. Include and Provenance revinclude
      # searches end in _search_test too, but run after the read test.
      PLAIN_SEARCH_TEST_ID = /\A(?!.*(?:_include_|_provenance_revinclude_)).*_search_test\z/

      def conformance_expectation
        plugin_data.dig("interaction", "expectation")
      end

      def resource_collection_string
        if group_metadata.delayed? && resource_type != "Provenance"
          "scratch.dig(:references, '#{resource_type}')"
        else
          "all_scratch_resources"
        end
      end

      # The resource IDs input for first-class read profiles: input_id, title, description and default. nil
      # for other profiles.
      def ids_input
        plugin_data["ids_input"]
      end

      # Delayed groups get their resources from references found by earlier groups, so their read test runs
      # first. Elsewhere it runs right after the searches that find the resources it reads, and before the
      # validation and must support tests that check what it read.
      def insert_index(tests)
        return 0 if group_metadata.delayed?

        last_search = tests.rindex { |test| PLAIN_SEARCH_TEST_ID.match?(test[:id]) }
        last_search ? last_search + 1 : 0
      end
    end
  end
end
