# frozen_string_literal: true

module Nombaone
  # A response object from the API. Every field is readable two ways:
  #
  #   customer.amount_in_kobo   # snake_case reader, derived from "amountInKobo"
  #   customer[:amount_in_kobo] # or bracket access (String/Symbol, snake or wire)
  #
  # Nested objects and arrays of objects are wrapped recursively, so
  # `subscription.items.first.price_id` just works. `metadata` (and any
  # free-form JSON) keeps its keys verbatim. Reach the raw wire Hash any time
  # with {#to_h}.
  #
  # The object also carries the {#request_id} for the call that produced it and
  # the raw {#last_response} (status + headers), for support and rate-limit
  # introspection.
  #
  # @example
  #   sub = nombaone.subscriptions.retrieve("nbo000000000001sub")
  #   sub.status                 # => "active"
  #   sub.current_period_end     # => "2026-08-05T00:00:00.000Z"
  #   sub.items.first.price_id   # => "nbo000000000001prc"
  #   sub[:latestInvoiceId]      # => "nbo000000000001inv"
  #   sub.request_id             # => "req_…"
  class NombaObject
    # @return [String, nil] the `meta.requestId` of the call that produced this.
    attr_reader :request_id
    # @return [Nombaone::Internal::Response, nil] the raw HTTP response.
    attr_reader :last_response

    # @param values [Hash] the parsed wire object (camelCase string keys).
    # @param request_id [String, nil]
    # @param response [Nombaone::Internal::Response, nil]
    # @api private
    def initialize(values, request_id: nil, response: nil)
      @values = values.is_a?(Hash) ? values : {}
      @converted = {}
      @request_id = request_id
      @last_response = response
    end

    # Read a field by snake_case or wire name (String or Symbol). Returns nil
    # when the field is absent — the lenient counterpart to a reader method
    # (which raises `NoMethodError` on an unknown field).
    #
    # @param key [String, Symbol]
    # @return [Object, nil]
    def [](key)
      wire = resolve_key(key)
      wire.nil? ? nil : converted(wire)
    end

    # Walk nested objects safely: `invoice.dig(:line_items, 0, :amount_in_kobo)`.
    #
    # @param keys [Array<String, Symbol, Integer>]
    # @return [Object, nil]
    def dig(*keys)
      keys.reduce(self) do |node, key|
        break nil if node.nil?
        break nil unless node.is_a?(NombaObject) || node.is_a?(Array) || node.is_a?(Hash)

        node[key]
      end
    end

    # @param key [String, Symbol]
    # @return [Boolean] whether the field is present.
    def key?(key)
      !resolve_key(key).nil?
    end
    alias has_key? key?
    alias member? key?

    # @return [Array<String>] the wire field names present on this object.
    def keys
      @values.keys
    end

    # The raw wire Hash, exactly as received (camelCase string keys, nested
    # Hashes/Arrays). Use this to serialize the object back or inspect the
    # untouched payload.
    #
    # @return [Hash]
    def to_h
      @values
    end
    alias to_hash to_h

    # Two objects are equal when their underlying wire Hashes are equal.
    # `request_id`/response metadata do not participate.
    #
    # @param other [Object]
    # @return [Boolean]
    def ==(other)
      other.is_a?(NombaObject) && other.to_h == @values
    end
    alias eql? ==

    # @return [Integer]
    def hash
      @values.hash
    end

    # @return [String]
    def inspect
      "#<#{self.class.name} #{@values.inspect}>"
    end

    # @api private
    def respond_to_missing?(name, include_private = false)
      name = name.to_s
      return false if name.end_with?("=", "?", "!")

      !resolve_key(name).nil? || super
    end

    # @api private
    def method_missing(name, *args)
      wire = args.empty? ? resolve_key(name) : nil
      return converted(wire) unless wire.nil?

      super
    end

    private

    # Resolve a caller-supplied key to the underlying wire key, matching either
    # the exact wire name (a camelCase field, or a verbatim `metadata` key) or
    # its snake_case form.
    def resolve_key(key)
      name = key.to_s
      return name if @values.key?(name)

      camel = Internal::Util.camelize(name)
      @values.key?(camel) ? camel : nil
    end

    def converted(wire_key)
      return @converted[wire_key] if @converted.key?(wire_key)

      @converted[wire_key] = wrap(@values[wire_key])
    end

    def wrap(value)
      case value
      when Hash then NombaObject.new(value)
      when Array then value.map { |item| wrap(item) }
      else value
      end
    end
  end
end
