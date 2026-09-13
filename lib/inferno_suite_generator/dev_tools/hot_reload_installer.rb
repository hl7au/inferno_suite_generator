# frozen_string_literal: true

require "fileutils"

module InfernoSuiteGenerator
  module DevTools
    # Installs/updates the shared `bin/hot-reload` watcher script into a
    # consumer test-kit project. Never overwrites a locally modified copy
    # unless force: true is passed.
    class HotReloadInstaller
      VERSION_COMMENT = /\A#!.*\n# inferno_suite_generator:hot-reload v(?<version>\d+)\n/

      def initialize(dest_path: "bin/hot-reload")
        @dest_path = dest_path
      end

      def source_path
        File.join(__dir__, "../assets/dev/hot-reload")
      end

      def source_version
        version_of(File.read(source_path))
      end

      def installed_version
        return nil unless File.exist?(@dest_path)

        version_of(File.read(@dest_path))
      end

      # :fresh        - nothing installed yet
      # :up_to_date   - installed and matches the shipped version marker
      # :outdated     - installed, unmodified content for its version, shipped version is newer
      # :modified     - installed, but its content doesn't match any known
      #                 version of the shipped script (local edits)
      def status
        return :fresh unless File.exist?(@dest_path)

        installed = File.read(@dest_path)
        return :modified if version_of(installed).nil?
        return :up_to_date if installed == File.read(source_path)

        :outdated
      end

      def install!(force: false)
        current = status
        if current == :modified && !force
          raise "#{@dest_path} has local changes (no recognizable version marker). " \
                "Re-run with force: true to overwrite, or diff it manually first."
        end
        return current if current == :up_to_date

        FileUtils.mkdir_p(File.dirname(@dest_path))
        FileUtils.cp(source_path, @dest_path)
        FileUtils.chmod(0o755, @dest_path)
        current == :fresh ? :installed : :updated
      end

      private

      def version_of(content)
        content[VERSION_COMMENT, :version]&.to_i
      end
    end
  end
end
