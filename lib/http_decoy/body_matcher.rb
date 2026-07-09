# frozen_string_literal: true

module HttpDecoy
  # Shared by the RSpec `have_received_request(...).with(body:)` chain and the
  # Minitest `assert_received_request(..., body:)` keyword — matches a logged
  # request body against either an exact Hash of expected key/value matchers
  # (each value tested via `===`, so RSpec matchers, classes, and regexes all
  # work) or a single matcher applied to the whole body.
  module BodyMatcher
    module_function

    # rubocop:disable Style/CaseEquality -- `===` is the point: callers pass
    # RSpec matchers, Regexp, Class, or plain values as `matcher`/`v`.
    def matches?(actual, matcher)
      case matcher
      when Hash
        actual.is_a?(Hash) && matcher.all? do |k, v|
          actual_val = actual[k] || actual[k.to_s]
          v === actual_val
        end
      else
        matcher === actual
      end
    end
    # rubocop:enable Style/CaseEquality
  end
end
