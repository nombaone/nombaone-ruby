# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "openssl"

module Nombaone
  module Internal
    # One raw HTTP round-trip's outcome: status, lower-cased headers, and the
    # unparsed body string.
    Response = Struct.new(:status, :headers, :body, keyword_init: true)

    # What the transport hands back on success: the unwrapped `data`, optional
    # cursor `pagination`, the `request_id`, and the raw {Response}.
    Result = Struct.new(:data, :pagination, :request_id, :response, keyword_init: true)

    # The default connection: a single `Net::HTTP` round-trip. Returns a
    # {Response} for **any** HTTP status (2xx, 4xx, 5xx alike) and raises only
    # on transport failure — a timeout ({Nombaone::TimeoutError}) or an
    # unreachable/broken connection ({Nombaone::ConnectionError}). Distinguishing
    # our own read timeout (a specific `Net::*Timeout`) from a caller's own
    # `Timeout.timeout` (a bare `Timeout::Error`, left to propagate) is what
    # lets the SDK retry the former and never retry the latter.
    class NetHTTPConnection
      METHOD_CLASSES = {
        get: Net::HTTP::Get,
        post: Net::HTTP::Post,
        patch: Net::HTTP::Patch,
        put: Net::HTTP::Put,
        delete: Net::HTTP::Delete,
      }.freeze

      # @return [Nombaone::Internal::Response]
      # @raise [Nombaone::TimeoutError, Nombaone::ConnectionError]
      def execute(method:, url:, headers:, body:, timeout:)
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = timeout
        http.read_timeout = timeout
        http.write_timeout = timeout if http.respond_to?(:write_timeout=)

        response = http.request(build_request(method, uri, headers, body))
        Response.new(status: response.code.to_i, headers: header_hash(response),
                     body: response.body)
      rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout
        raise Nombaone::TimeoutError, "The request to NombaOne timed out after #{timeout}s."
      rescue SocketError, SystemCallError, OpenSSL::SSL::SSLError, IOError,
             Net::HTTPBadResponse, Net::ProtocolError => e
        raise Nombaone::ConnectionError, "Could not reach the NombaOne API: #{e.message}"
      end

      private

      def build_request(method, uri, headers, body)
        klass = METHOD_CLASSES.fetch(method) { raise ArgumentError, "unsupported method #{method}" }
        request = klass.new(uri)
        headers.each { |name, value| request[name] = value }
        request.body = body unless body.nil?
        request
      end

      def header_hash(response)
        headers = {}
        response.each_header { |name, value| headers[name.downcase] = value }
        headers
      end
    end

    # Executes one logical API call: builds the request, runs the retry loop,
    # parses the response envelope, and returns a {Result} or raises a typed
    # error.
    #
    # Money-safety invariants enforced here and nowhere else:
    #
    # * The `Idempotency-Key` for a POST is computed **once, before the retry
    #   loop**, so every automatic retry replays the same logical operation
    #   instead of creating a new one.
    # * A caller-initiated cancellation is never retried; only timeouts,
    #   connection failures, 408/429/5xx, and our own in-flight idempotency
    #   conflict are.
    class HTTPClient
      # The version prefix is applied here, at exactly one place — never in a
      # resource path.
      API_PREFIX = "/v1"

      # Statuses retried unconditionally (409 is retried only for
      # `IDEMPOTENCY_IN_PROGRESS`, handled in {#retryable?}).
      RETRYABLE_STATUSES = [408, 429, 500, 502, 503, 504].freeze

      # @api private
      def initialize(api_key:, base_url:, timeout:, max_retries:, connection:,
                     default_headers: nil, sleeper: nil)
        @api_key = api_key
        @base_url = base_url
        @timeout = timeout
        @max_retries = max_retries
        @connection = connection
        @default_headers = default_headers
        @sleeper = sleeper || ->(seconds) { sleep(seconds) }
      end

      # @param method [Symbol] :get :post :patch :put :delete
      # @param path [String] path below `/v1`, segments already encoded.
      # @param query [Hash{String => String}, nil] wire-ready query params.
      # @param body [Hash, nil] wire-ready (camelCase) body, or nil for no body.
      # @param options [Hash] per-call options (idempotency_key, headers,
      #   timeout, max_retries, cancel_when).
      # @return [Nombaone::Internal::Result]
      def request(method:, path:, query: nil, body: nil, options: nil)
        options ||= {}
        timeout = options[:timeout] || @timeout
        max_retries = [options[:max_retries] || @max_retries, 0].max
        cancel_when = options[:cancel_when]

        url = build_url(path, query)
        headers = build_headers(method, body, options)
        payload = body.nil? ? nil : JSON.generate(body)

        attempt = 0
        loop do
          raise_if_canceled(cancel_when)

          begin
            response = @connection.execute(
              method: method, url: url, headers: headers, body: payload, timeout: timeout,
            )
          rescue Nombaone::TimeoutError, Nombaone::ConnectionError => e
            raise e if attempt >= max_retries

            wait(Util.backoff_seconds(attempt))
            attempt += 1
            next
          end

          parsed = parse_json(response.body)
          return build_result(response, parsed) if success_status?(response.status)

          error = APIError.from_response(response.status, parsed, response.headers)
          raise error unless attempt < max_retries && retryable?(response.status, error)

          retry_after = Util.retry_after_seconds(response.headers["retry-after"])
          wait(retry_after || Util.backoff_seconds(attempt))
          attempt += 1
        end
      end

      private

      def build_url(path, query)
        url = "#{@base_url}#{API_PREFIX}#{path}"
        return url if query.nil? || query.empty?

        "#{url}?#{URI.encode_www_form(query)}"
      end

      def build_headers(method, body, options)
        computed = {
          "authorization" => "Bearer #{@api_key}",
          "accept" => "application/json",
          "user-agent" => "nombaone-ruby/#{Nombaone::VERSION}",
        }
        computed["content-type"] = "application/json" unless body.nil?
        if method == :post
          computed["idempotency-key"] = options[:idempotency_key] || Util.generate_idempotency_key
        end
        Util.merge_headers(computed, @default_headers, options[:headers])
      end

      def success_status?(status)
        status.between?(200, 299)
      end

      def retryable?(status, error)
        RETRYABLE_STATUSES.include?(status) ||
          (status == 409 && error.code == ErrorCode::IDEMPOTENCY_IN_PROGRESS)
      end

      def raise_if_canceled(cancel_when)
        return unless cancel_when.respond_to?(:call) && cancel_when.call

        raise Nombaone::ConnectionError, "The request was canceled before it completed."
      end

      def wait(seconds)
        @sleeper.call(seconds) if seconds&.positive?
      end

      def parse_json(body)
        return nil if body.nil? || body.empty?

        JSON.parse(body)
      rescue JSON::ParserError
        nil
      end

      def build_result(response, parsed)
        unless parsed.is_a?(Hash) && parsed["success"] == true && parsed.key?("data")
          raise APIError.new(
            "The API returned a response that was not a valid NombaOne envelope.",
            status_code: response.status,
            code: ErrorCode::SYSTEM_INTERNAL_ERROR,
            request_id: response.headers["x-request-id"],
          )
        end

        request_id = parsed.dig("meta", "requestId")
        request_id = response.headers["x-request-id"] unless request_id.is_a?(String)

        Result.new(
          data: parsed["data"],
          pagination: parse_pagination(parsed["pagination"]),
          request_id: request_id,
          response: response,
        )
      end

      def parse_pagination(raw)
        return nil unless raw.is_a?(Hash) && [true, false].include?(raw["hasMore"])

        {
          limit: raw["limit"].is_a?(Integer) ? raw["limit"] : 0,
          has_more: raw["hasMore"],
          next_cursor: raw["nextCursor"].is_a?(String) ? raw["nextCursor"] : nil,
        }
      end
    end
  end
end
