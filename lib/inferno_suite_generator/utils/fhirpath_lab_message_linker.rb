# frozen_string_literal: true

require "cgi"
require "dry/container/error"
require "inferno/dsl/messages"
require_relative "fhirpath_lab_message_patterns"

module InfernoSuiteGenerator
  # Links messages that mention a FHIR resource and a FHIRPath expression to the FHIRPath Lab.
  module FhirpathLabMessageLinker
    module_function

    def linkify(message, base_url:, resource_base_url:, session_id:)
      return message unless message.is_a?(String)
      return message if base_url.blank? || resource_base_url.blank? || session_id.blank?

      match = FhirpathLabMessagePatterns.match(message)
      return message unless match

      "#{match[:resource_type]}/#{match[:resource_id]}: " \
        "#{echo_prefix(match)}" \
        "#{link_for(match, base_url:, resource_base_url:, session_id:)}: " \
        "#{match[:detail]}"
    end

    def echo_prefix(match)
      match[:echo] ? "#{match[:echo]}: " : ""
    end

    def link_for(match, base_url:, resource_base_url:, session_id:)
      resource_url = "#{resource_base_url.chomp("/")}/#{session_id}/#{match[:resource_type]}/#{match[:resource_id]}"
      query = "expression=#{CGI.escape(match[:path])}&engine=fhirpath.js&resource=#{CGI.escape(resource_url)}"

      "[#{match[:path]}](#{base_url.chomp("/")}?#{query})"
    end
  end

  # Patch Inferno::DSL::Messages to linkify messages that mention a FHIR resource and a FHIRPath expression.
  module MessagesFhirpathLabPatch
    def add_message(type, message)
      super(type, InfernoSuiteGenerator::FhirpathLabMessageLinker.linkify(
        message,
        base_url: fhirpathlab_url_for_message_linker,
        resource_base_url: resource_base_url_for_message_linker,
        session_id: test_session_id_for_message_linker
      ))
    end

    private

    def fhirpathlab_url_for_message_linker
      safely_for_message_linker { self.class.suite::FHIRPATHLAB_URL }
    end

    # A resource kept by this suite is reachable at this suite's own
    # `/custom/<suite_id>/resources` route (see resource_keeper_endpoints.rb)
    # rather than an externally configured URL.
    def resource_base_url_for_message_linker
      safely_for_message_linker { "#{Inferno::Application["base_url"]}/custom/#{self.class.suite.id}/resources" }
    end

    # `self.class.suite` raises NameError/NoMethodError for a runnable with no
    # suite, and `Inferno::Application[...]` raises Dry::Container::Error for
    # an unregistered key (e.g. before the host app finishes booting) — both
    # mean "can't build a link right now", so leave the message untouched.
    def safely_for_message_linker
      yield
    rescue NameError, Dry::Container::Error
      nil
    end

    def test_session_id_for_message_linker
      test_session_id if respond_to?(:test_session_id)
    end
  end
end

Inferno::DSL::Messages.prepend(InfernoSuiteGenerator::MessagesFhirpathLabPatch)
