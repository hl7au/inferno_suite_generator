# frozen_string_literal: true

module InfernoSuitePlugins
  module ProfileRead
    # Generates a read test for every group in the suite. Each group gets its read data under "profile_read" in
    # <group dir>/plugins.yml and a <group>_profile_read_test.rb at the end of its test list. The test runs
    # runtime/profile_read_test.rb, installed into <suite dir>/plugins/profile_read/.
    class Plugin < InfernoSuiteGenerator::Plugins::Base
      # Plugins are stateless: everything comes in through context.
      # :reek:UtilityFunction
      def generate(context)
        data_by_group = Extractor.extract(context)
        context.metadata.groups(data_by_group)
        ReadTestGenerator.generate(context, data_by_group)
        context.install_runtime
      end
    end
  end
end
