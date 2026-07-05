# frozen_string_literal: true

require "json"

module SpecSupport
  # A scripted transport double implementing the connection interface
  # (`#execute`). Every call is recorded (method, url, headers, parsed body)
  # and answered from a FIFO queue of scripted responses, so a test asserts on
  # exactly what the SDK put on the wire.
  class MockConnection
    Recorded = Struct.new(:http_method, :url, :headers, :body, :timeout, keyword_init: true)

    attr_reader :calls

    def initialize
      @calls = []
      @queue = []
    end

    # The connection interface the SDK's transport calls.
    def execute(method:, url:, headers:, body:, timeout:)
      @calls << Recorded.new(
        http_method: method,
        url: url,
        headers: headers,
        body: body.nil? ? nil : JSON.parse(body),
        timeout: timeout,
      )

      raise "MockConnection: no scripted response for #{method.upcase} #{url}" if @queue.empty?

      item = @queue.shift
      raise item[:error] if item[:kind] == :error

      Nombaone::Internal::Response.new(status: item[:status], headers: item[:headers],
                                       body: item[:body])
    end

    # Queue a raw response. `body` may be a String or a Ruby object (encoded).
    def respond(status, body, headers = {})
      @queue << {
        kind: :response,
        status: status,
        headers: normalize(headers),
        body: body.is_a?(String) ? body : JSON.generate(body),
      }
      self
    end

    # Queue a NombaOne success envelope wrapping `data`.
    def ok(data = {}, status: 200, request_id: "req_test")
      respond(status,
              { success: true, statusCode: status, data: data, meta: { requestId: request_id } })
    end

    # Queue a paginated success envelope.
    def page(data, has_more:, next_cursor:, limit: nil, request_id: "req_test")
      respond(200, {
                success: true,
                statusCode: 200,
                data: data,
                pagination: { limit: limit || data.length, hasMore: has_more,
                              nextCursor: next_cursor },
                meta: { requestId: request_id },
              })
    end

    # Queue a NombaOne error envelope.
    def fail(status, code:, message: "Something went wrong", hint: "Try again.",
             doc_url: nil, fields: nil, headers: {})
      error = { code: code, message: message, hint: hint }
      error[:docUrl] = doc_url || "https://docs.nombaone.xyz/errors##{code}"
      error[:fields] = fields if fields
      meta = { requestId: "req_test" }
      respond(status, { success: false, statusCode: status, error: error, meta: meta }, headers)
    end

    # Queue a transport-level connection failure.
    def network_error(error = nil)
      @queue << { kind: :error, error: error || Nombaone::ConnectionError.new("simulated network failure") }
      self
    end

    # Queue a transport-level timeout.
    def timeout_error
      network_error(Nombaone::TimeoutError.new("simulated timeout"))
    end

    private

    def normalize(headers)
      headers.each_with_object({}) { |(name, value), out| out[name.to_s.downcase] = value.to_s }
    end
  end
end
