# frozen_string_literal: true

require "json"
require "uri"

module SpecSupport
  # A connection that records every request's method + path and answers all of
  # them with a valid (empty) paginated envelope — so the whole SDK surface can
  # be exercised in one pass for conformance.
  class RecordingConnection
    Call = Struct.new(:http_method, :path, keyword_init: true)

    attr_reader :calls

    def initialize
      @calls = []
    end

    def execute(method:, url:, headers:, body:, timeout:)
      @calls << Call.new(http_method: method, path: URI.parse(url).path)
      Nombaone::Internal::Response.new(
        status: 200,
        headers: { "x-request-id" => "req_conformance" },
        body: JSON.generate(
          success: true,
          statusCode: 200,
          data: [],
          pagination: { limit: 20, hasMore: false, nextCursor: nil },
          meta: { requestId: "req_conformance" },
        ),
      )
    end
  end
end
