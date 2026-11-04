# frozen_string_literal: true

require_relative "usage_section"

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # Adds one "Used in questionnaires" section to the description of each test
    # in the Delivery::TestListings. An element counts as checked when any group
    # of the listing checks it.
    class TestSections
      READS = "A form can pre-fill an item only if the server returns the elements the item reads."
      GROUP_READS = "#{READS} Elements marked #{UsageSection::NOT_CHECKED} are neither Must Support nor required by " \
                    "the profile, so this group's tests do not check them.".freeze

      def initialize(listings)
        @listings = listings
      end

      def write(descriptions)
        @listings.each do |listing|
          destination = listing.destination
          section = section(listing)
          descriptions.test(destination.group, destination.test_id, section.markdown) unless section.empty?
        end
      end

      private

      def section(listing)
        groups = listing.groups
        group = groups.first
        UsageSection.new(listing.entries, group, intro: intro(listing.destination.kind, group.resource),
                                                 checked_by: groups)
      end

      # :reek:UtilityFunction
      def intro(kind, resource)
        case kind
        when "read"
          "These questionnaires in the IG read #{resource} resources as this test does: by id, or as the " \
          "resource a form is opened for. #{GROUP_READS}"
        when "search" then "These questionnaires in the IG make this search. #{GROUP_READS}"
        when "include" then include_intro(resource)
        when "create" then "These questionnaires in the IG create #{resource} resources from their answers."
        else "These questionnaires in the IG update existing #{resource} resources from their answers."
        end
      end

      # An include test belongs to another group than the entries it lists, and
      # those can be traced for several profiles.
      # :reek:UtilityFunction
      def include_intro(resource)
        "These questionnaires in the IG fetch #{resource} resources through this search's _include. #{READS} " \
          "Elements marked #{UsageSection::NOT_CHECKED} are neither Must Support nor required by any #{resource} " \
          "profile in this suite, so no test checks them."
      end
    end
  end
end
