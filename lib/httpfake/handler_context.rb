# frozen_string_literal: true

require "json"

module HttpFake
  # The `self` inside every route handler block.
  # Provides the full DSL surface: respond, requires_body, validates,
  # body, path_params, query_params, respond_sequence, raise_error.
  class HandlerContext
    class ContractError < StandardError
    end

    attr_reader :path_params, :query_params, :request

    # call_index: how many prior requests to this same (method, path) have been logged.
    # Used by respond_sequence to pick the right entry without storing mutable state.
    def initialize(rack_request, path_params, call_index: 0)
      @request     = rack_request
      @path_params = path_params
      @query_params = Rack::Utils.parse_nested_query(rack_request.query_string.to_s)
        .transform_keys(&:to_sym)
      @call_index  = call_index
      @_body       = :unset
      @_response   = nil
    end

    # Lazily parsed request body — memoized.
    def body
      return @_body unless @_body == :unset

      raw = @request.body&.read || ""
      @request.body&.rewind
      content_type = @request.content_type.to_s

      @_body = if content_type.include?("application/json")
                 raw.empty? ? {} : JSON.parse(raw, symbolize_names: true)
               elsif content_type.include?("application/x-www-form-urlencoded")
                 Rack::Utils.parse_nested_query(raw).transform_keys(&:to_sym)
               else
                 raw
               end
    end

    # Build and store the response tuple for this request.
    def respond(status, json: nil, text: nil, headers: {})
      body_str     = json ? JSON.generate(resolve(json)) : text.to_s
      content_type = json ? "application/json" : "text/plain"
      @_response   = [status.to_i, { "Content-Type" => content_type }.merge(headers), [body_str]]
    end

    # Stateful sequence: call_index picks which response to use.
    # Each entry is [status, { json: ..., text: ..., headers: ... }].
    # Wraps around if more calls are made than entries defined.
    def respond_sequence(*responses)
      entry  = responses[@call_index % responses.length]
      status = entry[0]
      opts   = entry[1] || {}
      respond(status, **opts)
    end

    # Contract assertion: raises ContractError if any key is absent from body.
    def requires_body(*keys)
      keys.each do |key|
        present = body.is_a?(Hash) && (body.key?(key) || body.key?(key.to_s))
        raise ContractError, "#{key} is required in request body" unless present
      end
    end

    # Type / range / enum validation on a body field.
    def validates(key, type: nil, min: nil, max: nil, inclusion: nil)
      value = body.is_a?(Hash) ? (body[key] || body[key.to_s]) : nil

      raise ContractError, "#{key} must be a #{type}, got #{value.class}" if type && !value.is_a?(type)
      raise ContractError, "#{key} must be >= #{min}, got #{value.inspect}" if min && value < min
      raise ContractError, "#{key} must be <= #{max}, got #{value.inspect}" if max && value > max
      return unless inclusion && !inclusion.include?(value)

      raise ContractError, "#{key} must be one of #{inclusion.inspect}, got #{value.inspect}"
    end

    # Simulate transport-level failures.
    def raise_error(type)
      case type
      when :timeout  then raise Timeout::Error, "httpfake simulated timeout"
      when :reset    then raise Errno::ECONNRESET, "httpfake simulated connection reset"
      when :refused  then raise Errno::ECONNREFUSED, "httpfake simulated connection refused"
      else                raise type.is_a?(Class) ? type : RuntimeError, type.to_s
      end
    end

    # Internal: the built response tuple, or nil if none was set.
    def response
      @_response
    end

    private

    # Recursively resolve lambdas in response bodies so users can write:
    #   respond 200, json: { id: -> { SecureRandom.uuid }, amount: -> { body[:amount] } }
    def resolve(obj)
      case obj
      when Hash  then obj.transform_values { |v| resolve(v) }
      when Array then obj.map { |v| resolve(v) }
      when Proc  then resolve(instance_exec(&obj))
      else            obj
      end
    end
  end
end
