# frozen_string_literal: true

module InfernoSuitePlugins
  module Read
    # Generates a read test per group with a read interaction, records them and their data in plugins.yml,
    # and installs the runtime module the tests include.
    class Plugin < InfernoSuiteGenerator::Plugins::Base
      # Plugins are stateless: everything comes in through context.
      # :reek:UtilityFunction
      def generate(context)
        data_by_group = Extractor.extract(context)
        context.metadata.groups(data_by_group)
        TestGenerator.generate(context, data_by_group)
        context.install_runtime
      end
    end
  end
end
