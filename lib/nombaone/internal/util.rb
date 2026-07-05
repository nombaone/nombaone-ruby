# frozen_string_literal: true

require "securerandom"
require "cgi"
require "time"

module Nombaone
  # @api private
  # Internal building blocks. Nothing here is part of the public API; it may
  # change between minor versions.
  module Internal
    # Sentinel for "the caller did not supply this optional argument."
    #
    # Optional keyword params default to {OMIT}. A key left as {OMIT} is
    # dropped from the request body entirely; an explicit `nil` is preserved
    # and sent as JSON `null` (the documented way to *clear* a nullable field
    # such as a customer's phone). This is the one reliable way in Ruby to tell
    # "absent" apart from "explicitly null."
    OMIT = Object.new
    OMIT.define_singleton_method(:inspect) { "#<Nombaone omitted>" }
    OMIT.freeze

    # Pure, dependency-free helpers shared across the transport and resources.
    module Util
      module_function

      # Keys whose *values* are arbitrary user JSON and must never have their
      # inner keys rewritten (a customer's `metadata`, a sandbox webhook
      # `payload`). The key name itself is still normalized (both are already
      # single words, so normalization is a no-op).
      PRESERVE_VALUE_KEYS = %w[metadata payload].freeze

      # Convert a snake_case key to the camelCase name the wire expects.
      # The wire field name is law; this is the single place the SDK's
      # idiomatic Ruby names become it (`customer_id` → `customerId`,
      # `amount_in_kobo` → `amountInKobo`, `plan_ref` → `planRef`).
      #
      # @param key [String, Symbol]
      # @return [String]
      def camelize(key)
        parts = key.to_s.split("_")
        return parts.first.to_s if parts.length <= 1

        head, *tail = parts
        (head + tail.map { |word| word.empty? ? "" : word[0].upcase + word[1..] }.join)
      end

      # Recursively rewrite Hash keys to camelCase, except that the value of a
      # {PRESERVE_VALUE_KEYS} key is passed through untouched.
      #
      # @param value [Object]
      # @return [Object]
      def deep_camelize_keys(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, val), out|
            out[camelize(key)] =
              PRESERVE_VALUE_KEYS.include?(key.to_s) ? val : deep_camelize_keys(val)
          end
        when Array
          value.map { |item| deep_camelize_keys(item) }
        else
          value
        end
      end

      # Prepare a request body hash for the wire: drop omitted keys (keeping
      # explicit `nil`s so nullable fields can be cleared), then camelize.
      #
      # @param hash [Hash]
      # @return [Hash]
      def serialize_body(hash)
        deep_camelize_keys(hash.reject { |_, v| OMIT.equal?(v) })
      end

      # Prepare query params: drop omitted **and** nil filters (an absent
      # filter, not a null one), camelize keys, and stringify values.
      #
      # @param hash [Hash]
      # @return [Hash{String => String}]
      def serialize_query(hash)
        hash.each_with_object({}) do |(key, value), out|
          next if OMIT.equal?(value) || value.nil?

          out[camelize(key)] = value.to_s
        end
      end

      # Percent-encode one URL path segment. Ids come from user input, so they
      # are never trusted raw; this matches JavaScript's `encodeURIComponent`
      # for the characters that appear in NombaOne ids.
      #
      # @param value [String]
      # @return [String]
      def encode_path_segment(value)
        CGI.escape(value.to_s).gsub("+", "%20")
      end

      # A fresh idempotency key for one logical POST. Computed once, before the
      # retry loop, so every automatic retry replays the same operation.
      #
      # @return [String]
      def generate_idempotency_key
        SecureRandom.uuid
      end

      # Full-jitter exponential backoff, in seconds: a random delay in
      # `[0, min(8, 0.5 * 2**attempt))`. Jitter keeps a fleet of retrying
      # clients from stampeding the API in lockstep.
      #
      # @param attempt [Integer] zero-based attempt index.
      # @return [Float]
      def backoff_seconds(attempt)
        rand * [8.0, 0.5 * (2**attempt)].min
      end

      # Parse a `Retry-After` header into seconds. Accepts delta-seconds or an
      # HTTP-date; returns nil when absent or unparseable so the caller falls
      # back to its own backoff.
      #
      # @param raw [String, nil]
      # @return [Float, nil]
      def retry_after_seconds(raw)
        return nil if raw.nil?

        seconds = Float(raw, exception: false)
        return [seconds, 0.0].max if seconds

        date = begin
          Time.httpdate(raw)
        rescue ArgumentError
          nil
        end
        date ? [date - Time.now, 0.0].max : nil
      end

      # Merge header layers left-to-right; later layers win. A `nil` value
      # deletes a header (lets a caller strip an SDK default for one request).
      # Header names are case-insensitive, so everything is lowercased once.
      #
      # @param layers [Array<Hash, nil>]
      # @return [Hash{String => String}]
      def merge_headers(*layers)
        layers.each_with_object({}) do |layer, out|
          next unless layer

          layer.each do |name, value|
            key = name.to_s.downcase
            value.nil? ? out.delete(key) : out[key] = value.to_s
          end
        end
      end
    end
  end
end
