# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"
require "inferno_suite_generator/dev_tools/hot_reload_installer"

module InfernoSuiteGenerator
  module DevTools
    class HotReloadInstallerTest < Minitest::Test
      def setup
        @dir = Dir.mktmpdir
        @dest_path = File.join(@dir, "bin/hot-reload")
        @installer = HotReloadInstaller.new(dest_path: @dest_path)
      end

      def teardown
        FileUtils.remove_entry(@dir)
      end

      def test_status_is_fresh_when_nothing_installed
        assert_equal :fresh, @installer.status
        assert_nil @installer.installed_version
      end

      def test_install_on_fresh_path_copies_file_and_returns_installed
        result = @installer.install!

        assert_equal :installed, result
        assert_path_exists @dest_path
        assert_equal File.read(@installer.source_path), File.read(@dest_path)
        assert_equal @installer.source_version, @installer.installed_version
      end

      def test_install_on_fresh_path_sets_executable_bit
        @installer.install!

        mode = File.stat(@dest_path).mode
        assert_equal 0o755, mode & 0o777
      end

      def test_install_again_with_no_changes_is_up_to_date_and_does_not_rewrite_file
        @installer.install!
        mtime_before = File.mtime(@dest_path)
        content_before = File.read(@dest_path)

        sleep 0.01
        result = @installer.install!

        assert_equal :up_to_date, result
        assert_equal mtime_before, File.mtime(@dest_path)
        assert_equal content_before, File.read(@dest_path)
      end

      def test_status_is_modified_when_dest_has_no_version_marker
        FileUtils.mkdir_p(File.dirname(@dest_path))
        File.write(@dest_path, "#!/bin/sh\necho unrelated\n")

        assert_equal :modified, @installer.status
        assert_nil @installer.installed_version
      end

      def test_install_raises_when_dest_is_modified_and_not_forced
        FileUtils.mkdir_p(File.dirname(@dest_path))
        File.write(@dest_path, "#!/bin/sh\necho unrelated\n")

        error = assert_raises(RuntimeError) { @installer.install! }
        assert_match(/local changes/, error.message)
      end

      def test_install_with_force_overwrites_modified_file
        FileUtils.mkdir_p(File.dirname(@dest_path))
        File.write(@dest_path, "#!/bin/sh\necho unrelated\n")

        result = @installer.install!(force: true)

        assert_equal :updated, result
        assert_equal File.read(@installer.source_path), File.read(@dest_path)
      end

      def test_status_is_outdated_when_installed_version_is_lower_than_shipped
        FileUtils.mkdir_p(File.dirname(@dest_path))
        File.write(@dest_path, "#!/bin/sh\n# inferno_suite_generator:hot-reload v0\necho old\n")

        assert_equal :outdated, @installer.status
        assert_equal 0, @installer.installed_version
      end

      def test_install_overwrites_outdated_file_and_returns_updated
        FileUtils.mkdir_p(File.dirname(@dest_path))
        File.write(@dest_path, "#!/bin/sh\n# inferno_suite_generator:hot-reload v0\necho old\n")

        result = @installer.install!

        assert_equal :updated, result
        assert_equal File.read(@installer.source_path), File.read(@dest_path)
      end
    end
  end
end
