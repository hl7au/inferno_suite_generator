# frozen_string_literal: true

require "bundler/gem_tasks"
require "rubocop/rake_task"
require "rake/testtask"

RuboCop::RakeTask.new

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.test_files = FileList["test/**/*_test.rb", "plugins/*/test/**/*_test.rb"]
end

namespace :plugins do
  desc "Create a plugin skeleton, e.g. rake 'plugins:new[my_plugin]' or rake 'plugins:new[my_plugin,path/to/dir]'"
  task :new, %i[id destination] do |_task, args|
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "inferno_suite_generator/plugins/scaffold"

    id = args.fetch(:id) { abort "Usage: rake 'plugins:new[my_plugin]'" }
    destination = args[:destination] || File.join("plugins", id)
    InfernoSuiteGenerator::Plugins::Scaffold.new(id:, destination:).create.each { |path| puts "create #{path}" }
  end
end

task default: :rubocop
