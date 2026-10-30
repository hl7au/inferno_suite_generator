# frozen_string_literal: true

require "fileutils"
require "yaml"

# Writes throwaway folder plugins for loader and runner tests. Each plugin gets its own class name, as plugin
# classes are global constants and tests run in one process.
module PluginFixtures
  def write_plugin(root, id:, class_name: nil, body: "def generate(context); end", **manifest)
    class_name ||= "PluginFixture#{id.split("_").map(&:capitalize).join}#{object_id}"
    FileUtils.mkdir_p(File.join(root, "lib"))
    File.write(
      File.join(root, "plugin.yml"),
      YAML.dump({ "id" => id, "name" => id, "version" => "1.0.0", "entrypoint" => "lib/#{id}.rb",
                  "class" => class_name }.merge(manifest.transform_keys(&:to_s)))
    )
    File.write(File.join(root, "lib", "#{id}.rb"), "class #{class_name}\n#{body}\nend\n")
    class_name
  end
end
