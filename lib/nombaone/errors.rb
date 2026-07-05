# frozen_string_literal: true

module Nombaone
  # Every public error code the API can emit, vendored verbatim from the
  # platform's `PUBLIC_ERROR_CODES`. Each constant's value is its own name
  # (e.g. `Nombaone::ErrorCode::CUSTOMER_NOT_FOUND == "CUSTOMER_NOT_FOUND"`),
  # so you can branch on `error.code == Nombaone::ErrorCode::CUSTOMER_NOT_FOUND`
  # without memorizing strings.
  #
  # The list is a **closed catalog shipped open**: a code the API adds tomorrow
  # is still parsed and surfaced on {APIError#code} as a plain string — it just
  # will not have a named constant here yet, and never breaks your code today.
  module ErrorCode
    # The full public catalog, in wire order.
    ALL = %w[
      CLIENT_INVALID_REQUEST
      CLIENT_VALIDATION_FAILED
      CLIENT_FORBIDDEN
      CLIENT_ROUTE_NOT_FOUND
      CLIENT_RESOURCE_NOT_FOUND
      CLIENT_CONFLICT
      INVALID_CURSOR
      API_KEY_MISSING
      API_KEY_INVALID
      API_KEY_SCOPE_FORBIDDEN
      API_KEY_ENVIRONMENT_MISMATCH
      API_KEY_HOST_MISMATCH
      IDEMPOTENCY_KEY_MISSING
      IDEMPOTENCY_KEY_REUSED
      IDEMPOTENCY_IN_PROGRESS
      RATE_LIMIT_EXCEEDED
      PLATFORM_MAINTENANCE
      WEBHOOK_SIGNATURE_INVALID
      CUSTOMER_NOT_FOUND
      CUSTOMER_EMAIL_TAKEN
      PLAN_NOT_FOUND
      PLAN_NAME_TAKEN
      PLAN_ALREADY_ARCHIVED
      PLAN_HAS_ACTIVE_SUBSCRIBERS
      PRICE_NOT_FOUND
      PRICE_PLAN_MISMATCH
      PRICE_ALREADY_INACTIVE
      PRICE_TIERED_NOT_SUPPORTED
      PAYMENT_METHOD_NOT_FOUND
      PAYMENT_METHOD_NOT_ACTIVE
      PAYMENT_METHOD_KIND_MISMATCH
      MANDATE_NOT_ACTIVE
      MANDATE_MAX_AMOUNT_EXCEEDED
      MANDATE_CONSENT_PENDING
      SUBSCRIPTION_NOT_FOUND
      SUBSCRIPTION_ILLEGAL_TRANSITION
      SUBSCRIPTION_VERSION_CONFLICT
      SUBSCRIPTION_NOT_TERMINAL
      SUBSCRIPTION_PAYMENT_METHOD_REQUIRED
      INVOICE_NOT_FOUND
      INVOICE_ALREADY_FINALIZED
      INVOICE_ALREADY_PAID
      INVOICE_NOT_VOIDABLE
      SUBSCRIPTION_SCHEDULE_NOT_FOUND
      SUBSCRIPTION_SCHEDULE_CONFLICT
      SUBSCRIPTION_SCHEDULE_INVALID_EFFECTIVE_AT
      PRORATION_NOT_APPLICABLE
      PRORATION_INTERVAL_SWITCH_UNSUPPORTED
      COUPON_NOT_FOUND
      COUPON_EXPIRED
      COUPON_MAX_REDEMPTIONS_REACHED
      COUPON_INVALID_DEFINITION
      COUPON_ALREADY_APPLIED
      DISCOUNT_NOT_FOUND
      CREDIT_GRANT_NOT_FOUND
      CREDIT_GRANT_ALREADY_VOIDED
      CREDIT_INSUFFICIENT_BALANCE
      CREDIT_INVALID_AMOUNT
      DUNNING_NO_OPEN_INVOICE
      DUNNING_ATTEMPT_NOT_FOUND
      DUNNING_CARD_UPDATE_REQUIRED
      DUNNING_ALREADY_TERMINAL
      SETTLEMENT_NOT_FOUND
      SETTLEMENT_SUBACCOUNT_NOT_FOUND
      REFUND_ALREADY_REFUNDED
      REFUND_AMOUNT_EXCEEDS_NET
      ESCROW_LOCKED
      PAYOUT_EXCEEDS_AVAILABLE
      QUOTA_EXCEEDED
      EXAMPLE_NOT_FOUND
      SYSTEM_INTERNAL_ERROR
      SYSTEM_UPSTREAM_ERROR
    ].freeze

    ALL.each { |code| const_set(code, code) }
  end

  # Base class for everything this SDK raises — API failures, connection
  # problems, webhook verification failures, and client misconfiguration.
  # Rescue `Nombaone::Error` to catch anything the SDK can throw.
  #
  # @example
  #   begin
  #     nombaone.subscriptions.create(customer_id: cus, price_id: prc)
  #   rescue Nombaone::Error => e
  #     warn e.message
  #   end
  class Error < StandardError; end

  # A non-2xx response from the API. Carries everything the error envelope
  # said: the stable {#code} to branch on, the {#hint} telling you how to fix
  # it, the {#doc_url} into the error reference, per-field validation errors on
  # 422s, and the {#request_id} to quote to support.
  #
  # Subclasses are keyed by HTTP status so `rescue` reads naturally:
  # {AuthenticationError}, {RateLimitError}, {ValidationError}, ….
  # Branch on {#code} (stable) or the class (by HTTP status), never on the
  # message (it may be reworded).
  class APIError < Error
    # @return [Integer] HTTP status of the response.
    attr_reader :status_code
    # @return [String] stable machine-readable error code — branch on this.
    attr_reader :code
    # @return [String] actionable guidance from the API on what to do next.
    attr_reader :hint
    # @return [String] deep link to this code's entry in the error reference.
    attr_reader :doc_url
    # @return [Hash{String => Array<String>}, nil] per-field validation errors,
    #   present on 422 responses.
    attr_reader :fields
    # @return [String, nil] the request id — include it when contacting support.
    attr_reader :request_id

    # @api private
    def initialize(message, status_code:, code:, hint: "", doc_url: "", fields: nil,
                   request_id: nil)
      # Surface the hint in the raised message itself — the fix should arrive
      # with the failure, without a docs tab.
      super(hint.nil? || hint.empty? ? message : "#{message} — #{hint}")
      @status_code = status_code
      @code = code
      @hint = hint || ""
      @doc_url = doc_url || ""
      @fields = fields
      @request_id = request_id
    end

    # Build the right {APIError} subclass from a raw response.
    #
    # @param status [Integer]
    # @param body [Object, nil] the parsed JSON body (nil if it was not JSON).
    # @param headers [#[]] response headers, looked up case-insensitively by
    #   lowercase name.
    # @return [APIError]
    # @api private
    def self.from_response(status, body, headers)
      parsed = parse_error_body(body)
      code = parsed[:code] || default_code_for_status(status)
      message = parsed[:message] || "Request failed with status #{status}"
      details = {
        status_code: status,
        code: code,
        hint: parsed[:hint] || "",
        doc_url: parsed[:doc_url] || "",
        request_id: parsed[:request_id] || headers["x-request-id"],
        fields: parsed[:fields],
      }

      klass = CLASS_FOR_STATUS[status] || (status >= 500 ? ServerError : APIError)
      return klass.new(message, **details) unless status == 429

      RateLimitError.new(
        message,
        retry_after: numeric(headers["retry-after"]),
        limit: numeric(headers["x-ratelimit-limit"]),
        remaining: numeric(headers["x-ratelimit-remaining"]),
        **details,
      )
    end

    # @api private
    def self.default_code_for_status(status)
      DEFAULT_CODE_FOR_STATUS.fetch(status, ErrorCode::SYSTEM_INTERNAL_ERROR)
    end

    # Pull `{ error: { code, message, hint, docUrl, fields }, meta: { requestId } }`
    # out of a parsed body, tolerating any missing or malformed piece — a proxy
    # 502 page must degrade to a clean error, never crash the parser.
    #
    # @api private
    def self.parse_error_body(body)
      return {} unless body.is_a?(Hash)

      error = body["error"]
      out = {}
      if error.is_a?(Hash)
        out[:code] = error["code"] if error["code"].is_a?(String)
        out[:message] = error["message"] if error["message"].is_a?(String)
        out[:hint] = error["hint"] if error["hint"].is_a?(String)
        out[:doc_url] = error["docUrl"] if error["docUrl"].is_a?(String)
        out[:fields] = error["fields"] if error["fields"].is_a?(Hash)
      end
      meta = body["meta"]
      out[:request_id] = meta["requestId"] if meta.is_a?(Hash) && meta["requestId"].is_a?(String)
      out
    end

    # @api private
    def self.numeric(value)
      return nil if value.nil?

      Integer(value)
    rescue ArgumentError, TypeError
      Float(value, exception: false)
    end

    private_class_method :parse_error_body, :numeric
  end

  # 400 — the request could not be understood.
  class BadRequestError < APIError; end
  # 401 — missing, invalid, revoked, or wrong-environment API key.
  class AuthenticationError < APIError; end
  # 403 — valid key, but not allowed (missing scope, foreign resource).
  class PermissionDeniedError < APIError; end
  # 404 — no resource at that id in this environment.
  class NotFoundError < APIError; end
  # 409 — conflicts with current state (including idempotency in-progress/reuse).
  class ConflictError < APIError; end
  # 422 — one or more fields invalid; see {APIError#fields}.
  class ValidationError < APIError; end
  # 5xx — something failed on NombaOne's side; safe to retry (the SDK already did).
  class ServerError < APIError; end

  # 429 — slow down; retry after {#retry_after} seconds. The SDK retries these
  # automatically, honoring `Retry-After`.
  class RateLimitError < APIError
    # @return [Integer, Float, nil] seconds until the rate-limit window rolls
    #   over (`Retry-After`).
    attr_reader :retry_after
    # @return [Integer, Float, nil] your request cap (`X-RateLimit-Limit`).
    attr_reader :limit
    # @return [Integer, Float, nil] requests left in the window
    #   (`X-RateLimit-Remaining`).
    attr_reader :remaining

    # @api private
    def initialize(message, retry_after: nil, limit: nil, remaining: nil, **details)
      super(message, **details)
      @retry_after = retry_after
      @limit = limit
      @remaining = remaining
    end
  end

  # The request never completed — DNS failure, connection reset, or a
  # caller-initiated cancellation.
  class ConnectionError < Error; end

  # A single attempt exceeded its timeout budget. Retried automatically.
  class TimeoutError < ConnectionError; end

  # Webhook signature or timestamp verification failed. Reject the delivery.
  class WebhookVerificationError < Error; end

  class APIError
    # Subclass dispatch by HTTP status (429 is special-cased in `from_response`).
    CLASS_FOR_STATUS = {
      400 => BadRequestError,
      401 => AuthenticationError,
      403 => PermissionDeniedError,
      404 => NotFoundError,
      409 => ConflictError,
      422 => ValidationError,
    }.freeze

    # The code to assume when the error body is missing or unusable.
    DEFAULT_CODE_FOR_STATUS = {
      400 => ErrorCode::CLIENT_INVALID_REQUEST,
      401 => ErrorCode::API_KEY_INVALID,
      403 => ErrorCode::CLIENT_FORBIDDEN,
      404 => ErrorCode::CLIENT_RESOURCE_NOT_FOUND,
      409 => ErrorCode::CLIENT_CONFLICT,
      422 => ErrorCode::CLIENT_VALIDATION_FAILED,
      429 => ErrorCode::RATE_LIMIT_EXCEEDED,
      502 => ErrorCode::SYSTEM_UPSTREAM_ERROR,
      503 => ErrorCode::SYSTEM_UPSTREAM_ERROR,
      504 => ErrorCode::SYSTEM_UPSTREAM_ERROR,
    }.freeze
  end
end
