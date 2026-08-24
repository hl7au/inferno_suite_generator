# frozen_string_literal: true

begin
  require "simplecov"
  SimpleCov.start do
    enable_coverage :branch
    track_files "lib/**/*.rb"
    add_filter "/test/"
    add_filter "/sig/"
  end
rescue LoadError
  warn "[test] simplecov not installed; skipping coverage collection"
end

require "minitest/autorun"

require "inferno_suite_generator/version"
require "json"

module FixtureHelpers
  def json_to_hash(file_path, symbolize_names: true)
    JSON.parse(File.read(file_path), symbolize_names:)
  end
end

unless defined?(Inferno::Application)
  module ::Inferno
    class Application
      class FakeLogger
        def error(*); end
      end

      FAKE_CONFIG = { "base_url" => "http://localhost:4567", "logger" => FakeLogger.new }.freeze

      def self.[](key)
        FAKE_CONFIG.fetch(key)
      end
    end
  end
end
