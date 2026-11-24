# frozen_string_literal: true

require "bundler/gem_tasks"
require "rubocop/rake_task"
require "rake/testtask"
require "reek/rake/task"

RuboCop::RakeTask.new

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.pattern = "test/**/*_test.rb"
end

# "." gives reek the same files as `reek .`; with no path it would read stdin when stdin is not a terminal.
Reek::Rake::Task.new { |task| task.source_files = "." }

task default: %i[test rubocop reek]
