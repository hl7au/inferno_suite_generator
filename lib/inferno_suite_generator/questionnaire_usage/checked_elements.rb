# frozen_string_literal: true

module InfernoSuiteGenerator
  module QuestionnaireUsage
    # The element paths the tests of one or more groups check: the ones their
    # profiles mark Must Support or require, and `id`.
    #
    # A path counts as checked when any of the groups checks it, and is labeled
    # as the group that checks it names it, so a slice one profile defines keeps
    # its name. A test can make the request of entries traced for several groups
    # of one type.
    class CheckedElements
      def initialize(groups)
        @profiles = groups.map { |group| Profile.new(group) }
      end

      def checked?(path)
        @profiles.any? { |profile| profile.checked?(path) }
      end

      # The path as sections show it: an extension the profile slices as Must
      # Support is named by its slice, like `extension:sliceName`, and any other
      # by the last part of its URL, like `extension[individual-pronouns]`.
      def label(path)
        (@profiles.find { |profile| profile.checked?(path) } || @profiles.first).label(path)
      end

      # The rule for one group's profile.
      #
      # Trace paths name an extension as `extension[url=U]`. A path inside an
      # extension the profile slices counts as checked, since the extension's
      # own profile defines what it holds.
      #
      # A trace path names a choice element by its type, like `valueQuantity`,
      # where the profile has `value[x]`, so it is compared as `value`.
      class Profile
        ALWAYS_PRESENT = %w[id].freeze
        EXTENSION_URL = /\A((?:modifierE|e)xtension)\[url=(.+)\]\z/
        EXTENSION_SLICE = /\A(?:modifierE|e)xtension:/

        def initialize(group)
          must_supports = group.must_supports || {}
          paths = element_paths(must_supports, group.mandatory_elements.to_a)
          @paths = paths.to_set { |path| plain(path) }
          @choices = choice_paths(paths)
          @slices = must_supports[:extensions].to_a.to_h { |extension| slice(extension) }
        end

        def label(path)
          sliced(path).gsub(%r{\[url=(?:[^\]]*/)?([^\]/]+)\]}, '[\1]')
        end

        def checked?(path)
          name = sliced(path)
          ALWAYS_PRESENT.include?(name) || @paths.include?(without_choice_types(name)) ||
            segments(name).any? { |segment| segment.match?(EXTENSION_SLICE) }
        end

        private

        # The path with each extension the profile slices named by its slice.
        def sliced(path)
          segments(path).each_with_object([]) do |segment, done|
            _, member, url = segment.match(EXTENSION_URL).to_a
            done << (@slices[[done.join("."), member, url]] || segment)
          end.join(".")
        end

        # Must Support element and slice paths are relative, like
        # `value[x]:valueQuantity.value` or `onset[x]` for an `onsetDateTime`
        # type slice; mandatory ones start with the type, like `Observation.status`.
        def element_paths(must_supports, mandatory)
          elements = must_supports[:elements].to_a + must_supports[:slices].to_a
          (elements.map { |element| element[:path] } + mandatory.map { |path| path.split(".", 2).last }).compact
        end

        # `[parent path, name]` for each choice element, like `["", "value"]`
        # for `value[x]:valueQuantity.value`.
        def choice_paths(paths)
          paths.filter_map do |path|
            parent, _, name = plain(path[/\A.*?\[x\]/]).rpartition(".") if path.include?("[x]")
            [parent, name] if name
          end.to_set
        end

        # The name with each segment that names a choice element by its type,
        # like `valueQuantity` or `effectiveDateTime`, written as the element.
        def without_choice_types(name)
          segments(name).each_with_object([]) do |segment, done|
            done << (choice_name(done.join("."), segment) || segment)
          end.join(".")
        end

        def choice_name(parent, segment)
          @choices.find { |choice_parent, name| choice_parent == parent && segment.match?(/\A#{name}[A-Z]/) }&.last
        end

        # `[[parent path, member, url], "extension:sliceName"]` for an extension
        # with an id like `Patient.address.extension:foo`.
        def slice(extension)
          parent, _, segment = extension[:id].to_s.split(".", 2).last.to_s.rpartition(".")
          [[plain(parent), segment.split(":").first, extension[:url]], segment]
        end

        # A snapshot path without `[x]` and slice names, as trace paths are.
        def plain(path)
          path.gsub("[x]", "").gsub(/:[^.]+/, "")
        end

        # Dot-separated steps, keeping the dots inside `[url=...]` together.
        def segments(path)
          path.scan(/(?:[^.\[]+|\[[^\]]*\])+/)
        end
      end
      private_constant :Profile
    end
  end
end
