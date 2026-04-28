# frozen_string_literal: true

require_relative "lib/inferno_suite_generator/version"

Gem::Specification.new do |spec|
  spec.name = "inferno_suite_generator"
  spec.version = InfernoSuiteGenerator::VERSION
  spec.authors = ["Pavel Rozhkov", "Ilya Beda"]
  spec.email = %w[prozskov@gmail.com pavel.r@beda.software ir4y.ix@gmail.com ilya@beda.software]

  spec.summary = "A Ruby gem for automatically generating test suites for FHIR Implementation Guides"
  spec.description = "Simplifies creating test suites to validate FHIR resources against Implementation Guides. " \
                     "Analyzes IG packages and generates Ruby test classes for the Inferno testing framework."
  spec.homepage = "https://github.com/hl7au/inferno_suite_generator"
  spec.license = "Apache-2.0"
  spec.required_ruby_version = "= 3.3.6"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/hl7au/inferno_suite_generator"
  spec.metadata["changelog_uri"] = "https://github.com/hl7au/inferno_suite_generator/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "deep_merge", "~> 1.2", ">= 1.2.2"
  spec.add_dependency "inferno_core", ">= 1.0.6"
  spec.add_dependency "jsonpath", "~> 1.1", ">= 1.1.5"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
