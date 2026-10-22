# frozen_string_literal: true

require "erb"
require "fileutils"
require_relative "error"
require_relative "../utils/naming"

module InfernoSuiteGenerator
  module Plugins
    # Base class for a plugin's template-driven test generator. It renders one ERB template from the plugin's
    # templates directory per group, writes it into the group directory and adds the test to the group's test
    # list, so the host's group generator requires and runs it like a built-in test. Each generated test is
    # also appended to "tests" in the plugin's section of the group's plugins.yml.
    #
    #   class ReadTestGenerator < InfernoSuiteGenerator::Plugins::TestGenerator
    #     self.template_name = "read.rb.erb"
    #     self.class_name_suffix = "ReadTest"     # => PatientReadTest
    #     self.test_id_suffix = "read_test"       # => au_core_v200_patient_read_test
    #   end
    #
    # The template is rendered against the generator instance, so it can call the public methods below and any
    # the subclass adds. Override insert_index to place the test somewhere other than the end of the group.
    # Generating a test whose id the group already has (from the host or another plugin) raises Plugins::Error.
    #
    # Its public methods are the API templates and subclasses build on, so it has many of them on purpose.
    # :reek:TooManyMethods
    class TestGenerator
      class_attribute :template_name, :class_name_suffix, :test_id_suffix

      attr_reader :context, :group_metadata, :plugin_data

      def self.generate(context, data_by_group)
        data_by_group.map { |group_metadata, data| new(context, group_metadata, data).tap(&:generate) }
      end

      def initialize(context, group_metadata, plugin_data = {})
        @context = context
        @group_metadata = group_metadata
        @plugin_data = plugin_data
      end

      def ig_metadata
        context.ig_metadata
      end

      # e.g. AUCoreTestKit
      def suite_module_name
        context.config.suite_module_name
      end

      # e.g. AUCoreV200
      def module_name
        "#{ig_metadata.ig_module_name_prefix}#{group_metadata.reformatted_version.upcase}"
      end

      def resource_type
        group_metadata.resource
      end

      # The group's directory name, e.g. patient or bloodpressure. Same as the host's group generator uses.
      def profile_identifier
        Generator::Naming.snake_case_for_profile(group_metadata)
      end

      # e.g. Patient; class_name appends class_name_suffix.
      def base_class_name
        Generator::Naming.upper_camel_case_for_profile(group_metadata)
      end

      # e.g. au_core_v200_patient, which is also the group's id; test_id appends test_id_suffix.
      def base_test_id
        "#{ig_metadata.ig_test_id_prefix}_#{group_metadata.reformatted_version}_#{profile_identifier}"
      end

      def class_name
        "#{base_class_name}#{class_name_suffix}"
      end

      def test_id
        "#{base_test_id}_#{test_id_suffix}"
      end

      def output_file_directory
        File.join(context.base_output_dir, profile_identifier)
      end

      def base_output_file_name
        "#{class_name.underscore}.rb"
      end

      def output_file_name
        File.join(output_file_directory, base_output_file_name)
      end

      def template
        @template ||= File.read(context.template_path(template_name))
      end

      def output
        @output ||= ERB.new(template).result(binding)
      end

      # Where the test goes in the group's test list, which holds every built-in test by the time plugins run.
      # Inferno runs a group's tests in this order. Defaults to the end; subclasses override it.
      # :reek:UtilityFunction
      def insert_index(tests)
        tests.length
      end

      def generate
        tests = (group_metadata.tests ||= [])
        check_test_id_is_free(tests)
        write_test_file
        register_test(tests, { id: test_id, file_name: base_output_file_name })
      end

      private

      def write_test_file
        FileUtils.mkdir_p(output_file_directory)
        File.write(output_file_name, output)
      end

      def register_test(tests, test)
        tests.insert(insert_index(tests), test)
        context.metadata.group(group_metadata, { "tests" => [test] })
      end

      def check_test_id_is_free(tests)
        return unless tests.any? { |test| test[:id] == test_id }

        raise Error, "Plugin #{context.plugin_id} generates test #{test_id}, which group " \
                     "#{group_metadata.name} already has. Disable one of the two generators."
      end
    end
  end
end
