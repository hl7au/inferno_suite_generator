# frozen_string_literal: true

require "fhir_models"
require "inferno/ext/fhir_models"

require_relative "inferno_suite_generator/utils/set_by_path"
require_relative "inferno_suite_generator/core/ig_loader"
require_relative "inferno_suite_generator/extractors/ig_metadata_extractor"
require_relative "inferno_suite_generator/extractors/ig_demodata_extractor"
require_relative "inferno_suite_generator/generators/group_generator"
require_relative "inferno_suite_generator/generators/must_support_test_generator"
require_relative "inferno_suite_generator/generators/provenance_revinclude_search_test_generator"
require_relative "inferno_suite_generator/generators/read_test_generator"
require_relative "inferno_suite_generator/generators/reference_resolution_test_generator"
require_relative "inferno_suite_generator/generators/search_test_generator"
require_relative "inferno_suite_generator/generators/suite_generator"
require_relative "inferno_suite_generator/generators/validation_test_generator"
require_relative "inferno_suite_generator/generators/multiple_or_search_test_generator"
require_relative "inferno_suite_generator/generators/multiple_and_search_test_generator"
require_relative "inferno_suite_generator/generators/chain_search_test_generator"
require_relative "inferno_suite_generator/generators/include_search_test_generator"
require_relative "inferno_suite_generator/generators/create_test_generator"
require_relative "inferno_suite_generator/generators/update_test_generator"
require_relative "inferno_suite_generator/generators/patch_test_generator"
require_relative "inferno_suite_generator/core/generator_config_keeper"
require_relative "inferno_suite_generator/utils/registry"
require_relative "inferno_suite_generator/utils/helpers"

module InfernoSuiteGenerator
  class Generator
    def self.generate(config_path = nil)
      Registry.register(:config_keeper, GeneratorConfigKeeper.new(config_path))
      config = Registry.get(:config_keeper)
      new(config.ig_deps_path).generate
    end

    attr_accessor :ig_resources, :ig_metadata, :ig_deps_path, :ig_demodata

    def initialize(ig_deps_path)
      self.ig_deps_path = ig_deps_path
    end

    def generate
      load_ig_package
      extract_metadata
      extract_demodata
      generate_search_tests
      generate_read_tests
      generate_provenance_revinclude_search_tests
      generate_include_search_tests
      generate_validation_tests
      generate_must_support_tests
      generate_reference_resolution_tests
      generate_create_tests
      generate_update_tests
      generate_patch_tests
      generate_groups
      generate_suites
      use_tests
    end

    def extract_metadata
      self.ig_metadata = IGMetadataExtractor.new(ig_resources).extract

      FileUtils.mkdir_p(base_output_dir)
      File.write(File.join(base_output_dir, "metadata.yml"), YAML.dump(ig_metadata.to_hash))
    end

    def extract_demodata
      self.ig_demodata = IGDemodataExtractor.new(ig_resources, ig_metadata).extract

      FileUtils.mkdir_p(base_output_dir)
      File.write(File.join(base_output_dir, "demodata.yml"), YAML.dump(ig_demodata.to_hash))
    end

    def base_output_dir
      File.join(Registry.get(:config_keeper).result_folder, ig_metadata.ig_version)
    end

    def load_ig_package
      FHIR.logger = Logger.new(File::NULL)
      self.ig_resources = IGLoader.new(ig_deps_path).load
    end

    def generate_reference_resolution_tests
      ReferenceResolutionTestGenerator.generate(ig_metadata, base_output_dir)
    end

    def generate_must_support_tests
      MustSupportTestGenerator.generate(ig_metadata, base_output_dir)
    end

    def generate_validation_tests
      ValidationTestGenerator.generate(ig_metadata, base_output_dir)
      generate_custom_tests_with_type("validation")
    end

    def generate_read_tests
      ReadTestGenerator.generate(ig_metadata, base_output_dir)
      generate_custom_tests_with_type("read")
    end

    def generate_search_tests
      SearchTestGenerator.generate(ig_metadata, base_output_dir)
      generate_multiple_or_search_tests
      generate_multiple_and_search_tests
      generate_chain_search_tests
      generate_custom_tests_with_type("search")
    end

    def generate_custom_tests_with_type(test_type)
      custom_generators = Registry.get(:config_keeper).custom_generators.select do |generator_config|
        generator_config["test_type"] == test_type
      end

      custom_generators.each do |generator_config|
        use_custom_generator(generator_config)
      end
    end

    def use_custom_generator(generator_config)
      generator_path = generator_config["path_to_generator"]
      generator_class = generator_config["generator_class"]
      template_path = generator_config["path_to_template"]

      begin
        absolute_generator_path = File.expand_path(generator_path, Dir.pwd)
        absolute_template_path = File.expand_path(template_path, Dir.pwd)

        require absolute_generator_path

        generator_class = Object.const_get(generator_class)

        puts "Loading custom generator: #{generator_class}"
        generator_class.generate(ig_metadata, base_output_dir, absolute_template_path)
      rescue StandardError => e
        puts "Error loading custom generator: #{e.message}"
        puts e.backtrace.join("\n")
      end
    end

    def generate_include_search_tests
      IncludeSearchTestGenerator.generate(ig_metadata, base_output_dir)
    end

    def generate_provenance_revinclude_search_tests
      ProvenanceRevincludeSearchTestGenerator.generate(ig_metadata, base_output_dir)
    end

    def generate_multiple_or_search_tests
      MultipleOrSearchTestGenerator.generate(ig_metadata, base_output_dir)
    end

    def generate_multiple_and_search_tests
      MultipleAndSearchTestGenerator.generate(ig_metadata, base_output_dir)
    end

    def generate_chain_search_tests
      ChainSearchTestGenerator.generate(ig_metadata, base_output_dir)
    end

    def generate_create_tests
      CreateTestGenerator.generate(ig_metadata, base_output_dir, ig_resources)
    end

    def generate_update_tests
      UpdateTestGenerator.generate(ig_metadata, base_output_dir)
    end

    def generate_patch_tests
      PatchTestGenerator.generate(ig_metadata, base_output_dir, ig_resources)
    end

    def generate_groups
      GroupGenerator.generate(ig_metadata, base_output_dir)
    end

    def generate_suites
      SuiteGenerator.generate(ig_metadata, base_output_dir)
    end

    def use_tests
      config = Registry.get(:config_keeper)
      main_file = config.main_file_path
      file_path = File.expand_path(main_file, Dir.pwd)
      related_result_folder = Registry.get(:config_keeper).result_folder

      test_suite_file_name = "#{ig_metadata.ig_test_id_prefix}_test_suite"

      require_path = File.join(
        related_result_folder.split("/opt/inferno/lib/").last,
        ig_metadata.ig_version,
        test_suite_file_name
      )

      require_path = require_path.gsub("./lib/", "")

      file_content = File.read(file_path)
      string_to_add = "require_relative '#{require_path}'"

      return if file_content.include? string_to_add

      file_content << "\n#{string_to_add}"
      File.write(file_path, file_content)
    end
  end
end
