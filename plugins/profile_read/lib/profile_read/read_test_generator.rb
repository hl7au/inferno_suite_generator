# frozen_string_literal: true

module InfernoSuitePlugins
  module ProfileRead
    # Renders templates/profile_read.rb.erb into each group, e.g. patient/patient_profile_read_test.rb with
    # id au_core_v200_patient_profile_read_test. plugin_data is the group's Extractor result.
    class ReadTestGenerator < InfernoSuiteGenerator::Plugins::TestGenerator
      self.template_name = "profile_read.rb.erb"
      self.class_name_suffix = "ProfileReadTest"
      self.test_id_suffix = "profile_read_test"

      # Inputs are shared across a suite's groups, so the name carries the group's directory name.
      def ids_input_name
        "#{profile_identifier}_profile_read_ids"
      end

      def profile_name
        group_metadata.profile_name || group_metadata.title || resource_type
      end

      def title
        "Server returns a #{resource_type} that conforms to #{profile_name} for each id"
      end

      def description
        <<~MARKDOWN.strip
          Reads each id in **#{input_title}** with `GET [base]/#{resource_type}/[id]` and checks that the server returns HTTP 200 and a #{resource_type} with that id.#{validation_sentence}

          The test is skipped when no ids are given. #{expectation_sentence}
        MARKDOWN
      end

      def input_title
        "#{profile_name} ids to read"
      end

      def input_description
        "Comma separated #{resource_type} ids. Defaults to the ids of the IG examples that claim #{profile_url}."
      end

      def default_ids
        Array(plugin_data["example_ids"]).join(", ")
      end

      def optional?
        plugin_data["expectation"] != "SHALL"
      end

      private

      def profile_url
        plugin_data["profile_url"]
      end

      def validation_sentence
        return "" unless plugin_data["validate"]

        " Each resource is then validated against #{profile_url}."
      end

      def expectation_sentence
        expectation = plugin_data["expectation"]
        case expectation
        when "SHALL" then "The CapabilityStatement says servers SHALL support read for #{resource_type}."
        when String then "The CapabilityStatement says servers #{expectation} support read for #{resource_type}, " \
                         "so the test is optional."
        else "The CapabilityStatement doesn't declare read for #{resource_type}, so the test is optional."
        end
      end
    end
  end
end
