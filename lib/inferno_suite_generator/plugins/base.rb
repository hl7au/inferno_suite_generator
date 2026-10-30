# frozen_string_literal: true

module InfernoSuiteGenerator
  module Plugins
    # The plugin contract: the host creates the class named in plugin.yml with no arguments and calls
    # generate with a Context. Inheriting from Base is optional; any class with that shape is a plugin.
    class Base
      # generate(context), generate(*args) and generate(context, *rest) all accept one argument.
      GENERATE_ARITIES = [1, -1, -2].freeze

      def self.implemented_by?(instance)
        GENERATE_ARITIES.include?(instance.method(:generate).arity)
      rescue NameError
        false
      end

      def generate(_context)
        raise NotImplementedError, "#{self.class} must implement generate(context)"
      end
    end
  end
end
