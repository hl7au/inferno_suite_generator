# frozen_string_literal: true

require "cgi"
require "inferno/dsl/messages"

module InfernoSuiteGenerator
  module FhirpathLabMessageLinker
    MESSAGE_PATTERN = %r{
      \A
      (?<resource_type>[A-Za-z][A-Za-z0-9]*)/(?<resource_id>[^\s:]+):\x20
      (?<path>[^:\n]+):\x20
      (?<detail>.*)
      \z
    }mx

    module_function

    def linkify(message, base_url:, resource_keeper_url:, session_id:)
      return message unless message.is_a?(String)
      return message if base_url.blank? || resource_keeper_url.blank? || session_id.blank?

      match = MESSAGE_PATTERN.match(message)
      return message unless match

      "#{match[:resource_type]}/#{match[:resource_id]}: " \
        "#{link_for(match, base_url:, resource_keeper_url:, session_id:)}: " \
        "#{match[:detail]}"
    end

    def link_for(match, base_url:, resource_keeper_url:, session_id:)
      resource_url = "#{resource_keeper_url.chomp("/")}/#{session_id}/#{match[:resource_type]}/#{match[:resource_id]}"
      query = "expression=#{CGI.escape(match[:path])}&engine=fhirpath.js&resource=#{CGI.escape(resource_url)}"

      "[#{match[:path]}](#{base_url.chomp("/")}?#{query})"
    end
  end

  module MessagesFhirpathLabPatch
    def add_message(type, message)
      super(type, InfernoSuiteGenerator::FhirpathLabMessageLinker.linkify(
        message,
        base_url: fhirpathlab_url_for_message_linker,
        resource_keeper_url: resource_keeper_url_for_message_linker,
        session_id: test_session_id_for_message_linker
      ))
    end

    private

    def fhirpathlab_url_for_message_linker
      self.class.suite::FHIRPATHLAB_URL
    rescue NameError
      nil
    end

    def resource_keeper_url_for_message_linker
      self.class.suite::RESOURCE_KEEPER_URL
    rescue NameError
      nil
    end

    def test_session_id_for_message_linker
      test_session_id if respond_to?(:test_session_id)
    end
  end
end

Inferno::DSL::Messages.prepend(InfernoSuiteGenerator::MessagesFhirpathLabPatch)
