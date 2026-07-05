# frozen_string_literal: true

require "openssl"
require "json"

module Nombaone
  # Verify and parse incoming NombaOne webhook deliveries.
  #
  # Available as `nombaone.webhooks` on a client, or standalone via
  # {Nombaone.webhooks} — verification needs only the endpoint's signing secret,
  # never an API key, so it works in a receiver that never builds a client.
  #
  # **Feed it the raw request body.** Parsing and re-serializing JSON can
  # reorder keys and change bytes, which breaks the signature. Capture the body
  # before any middleware parses it (`request.raw_post` in Rack/Rails).
  #
  # @example Rails controller
  #   def receive
  #     event = Nombaone.webhooks.construct_event(
  #       request.raw_post,
  #       request.headers["X-Nombaone-Signature"],
  #       ENV.fetch("NOMBAONE_WEBHOOK_SECRET"),
  #     )
  #     return head(:ok) if already_processed?(event.event.id) # at-least-once ⇒ dedupe
  #
  #     unlock(event.data.reference) if event.type == Nombaone::WebhookEventType::INVOICE_PAID
  #     head :ok # respond 2xx fast; do heavy work async
  #   rescue Nombaone::WebhookVerificationError
  #     head :bad_request
  #   end
  class Webhooks
    # Maximum allowed age (seconds) between the delivery's `t` timestamp and now.
    DEFAULT_TOLERANCE_SECONDS = 300

    # Verify a delivery's signature and timestamp, then parse and return the
    # typed event. This is the one call your handler needs.
    #
    # @param payload [String] the exact raw request body.
    # @param signature_header [String] the `X-Nombaone-Signature` header value.
    # @param secret [String] the endpoint's signing secret (shown once at creation).
    # @param tolerance [Numeric] max timestamp age in seconds (default 300).
    # @return [WebhookEvent]
    # @raise [WebhookVerificationError] on a missing/malformed header, a stale
    #   timestamp, an invalid signature, or a non-JSON body.
    def construct_event(payload, signature_header, secret, tolerance: DEFAULT_TOLERANCE_SECONDS)
      verify_signature(payload, signature_header, secret, tolerance: tolerance)

      begin
        parsed = JSON.parse(payload.to_s)
      rescue JSON::ParserError
        raise WebhookVerificationError, "Webhook payload was not valid JSON."
      end
      unless parsed.is_a?(Hash)
        raise WebhookVerificationError, "Webhook payload was not a JSON object."
      end

      WebhookEvent.new(ensure_event_block(parsed))
    end

    # Verify a delivery's signature and timestamp only (no parse). Returns true
    # on success; raises with a distinct message per failure mode.
    #
    # @param payload [String] the exact raw request body.
    # @param signature_header [String] the `X-Nombaone-Signature` header value.
    # @param secret [String] the endpoint's signing secret.
    # @param tolerance [Numeric] max timestamp age in seconds (default 300).
    # @return [true]
    # @raise [WebhookVerificationError]
    def verify_signature(payload, signature_header, secret, tolerance: DEFAULT_TOLERANCE_SECONDS)
      if signature_header.nil? || signature_header.empty?
        raise WebhookVerificationError,
              "Missing X-Nombaone-Signature header — is this request really from NombaOne?"
      end
      if secret.nil? || secret.empty?
        raise WebhookVerificationError,
              "Missing signing secret — pass the secret shown when the endpoint was created."
      end

      timestamp, signatures = parse_signature_header(signature_header)
      assert_within_tolerance(timestamp, tolerance)

      expected = compute_signature(secret, timestamp, payload.to_s)
      return true if signatures.any? { |candidate| secure_compare(candidate, expected) }

      raise WebhookVerificationError,
            "Webhook signature verification failed — check you are using this endpoint's " \
            "current signing secret and the exact raw request body (no re-serialization)."
    end

    # Build a valid `X-Nombaone-Signature` header for a payload — for testing
    # your own handler without waiting on a real delivery.
    #
    # @param payload [String] the raw body you will pass to {#construct_event}.
    # @param secret [String] the signing secret.
    # @param timestamp [Integer, nil] unix seconds (defaults to now).
    # @return [String] a `t=<unix>,v1=<hex>` header value.
    #
    # @example
    #   header = Nombaone.webhooks.generate_test_header(payload: body, secret: secret)
    #   event = Nombaone.webhooks.construct_event(body, header, secret)
    def generate_test_header(payload:, secret:, timestamp: nil)
      timestamp = (timestamp || Time.now.to_i).to_s
      "t=#{timestamp},v1=#{compute_signature(secret, timestamp, payload.to_s)}"
    end

    private

    def compute_signature(secret, timestamp, raw_body)
      OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{raw_body}")
    end

    def parse_signature_header(header)
      timestamp = nil
      signatures = []
      header.split(",").each do |pair|
        eq = pair.index("=")
        next if eq.nil?

        key = pair[0...eq].strip
        value = pair[(eq + 1)..].strip
        timestamp = value if key == "t"
        # Multiple `v1` entries are legal during secret rotation — any match passes.
        signatures << value if key == "v1" && !value.empty?
      end

      if timestamp.nil? || signatures.empty?
        raise WebhookVerificationError,
              'Malformed X-Nombaone-Signature header — expected "t=<unix>,v1=<hex>".'
      end
      [timestamp, signatures]
    end

    def assert_within_tolerance(timestamp, tolerance)
      seconds = Integer(timestamp, exception: false)
      if seconds.nil?
        raise WebhookVerificationError,
              "Malformed X-Nombaone-Signature header — `t` is not a unix timestamp."
      end

      age = (Time.now.to_i - seconds).abs
      return if age <= tolerance

      raise WebhookVerificationError,
            "Webhook timestamp is outside the allowed tolerance (#{age}s old, limit " \
            "#{tolerance}s) — possible replay, or severe clock skew."
    end

    def secure_compare(candidate, expected)
      candidate.bytesize == expected.bytesize &&
        OpenSSL.fixed_length_secure_compare(candidate, expected)
    end

    # Guarantee a dedupe-able `event.id` even if a delivery body arrives flat
    # (older shape) — fall back to top-level fields.
    def ensure_event_block(body)
      return body if body["event"].is_a?(Hash)

      body.merge(
        "event" => {
          "id" => body["id"].is_a?(String) ? body["id"] : "",
          "type" => body["type"].is_a?(String) ? body["type"] : "",
          "createdAt" => body["createdAt"].is_a?(String) ? body["createdAt"] : "",
        },
      )
    end
  end
end
