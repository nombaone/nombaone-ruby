# frozen_string_literal: true

RSpec.describe Nombaone::APIError do
  def error_body(code:, message: "It failed", hint: "Fix it",
                 doc_url: "https://docs.nombaone.xyz/errors##{code}", fields: nil)
    error = { "code" => code, "message" => message, "hint" => hint, "docUrl" => doc_url }
    error["fields"] = fields if fields
    { "success" => false, "statusCode" => 0, "error" => error,
      "meta" => { "requestId" => "req_z" } }
  end

  describe ".from_response" do
    {
      400 => Nombaone::BadRequestError,
      401 => Nombaone::AuthenticationError,
      403 => Nombaone::PermissionDeniedError,
      404 => Nombaone::NotFoundError,
      409 => Nombaone::ConflictError,
      422 => Nombaone::ValidationError,
      500 => Nombaone::ServerError,
      503 => Nombaone::ServerError,
    }.each do |status, klass|
      it "maps #{status} to #{klass}" do
        error = described_class.from_response(status, error_body(code: "X"), {})
        expect(error).to be_a(klass)
        expect(error.status_code).to eq(status)
      end
    end

    it "renders the hint into the message so the fix arrives with the failure" do
      body = error_body(
        code: "CUSTOMER_NOT_FOUND", message: "No such customer", hint: "Check the id",
      )
      error = described_class.from_response(404, body, {})
      expect(error.message).to eq("No such customer — Check the id")
      expect(error.code).to eq(Nombaone::ErrorCode::CUSTOMER_NOT_FOUND)
      expect(error.hint).to eq("Check the id")
      expect(error.doc_url).to include("CUSTOMER_NOT_FOUND")
    end

    it "carries per-field errors on 422" do
      body = error_body(code: "CLIENT_VALIDATION_FAILED", fields: { "email" => ["Invalid email"] })
      error = described_class.from_response(422, body, {})
      expect(error).to be_a(Nombaone::ValidationError)
      expect(error.fields).to eq("email" => ["Invalid email"])
    end

    it "takes request_id from the body, falling back to the X-Request-Id header" do
      from_body = described_class.from_response(404, error_body(code: "X"), {})
      expect(from_body.request_id).to eq("req_z")

      headers_only = described_class.from_response(404, nil, { "x-request-id" => "req_header" })
      expect(headers_only.request_id).to eq("req_header")
    end

    it "exposes rate-limit details on 429" do
      error = described_class.from_response(
        429,
        error_body(code: "RATE_LIMIT_EXCEEDED"),
        { "retry-after" => "17", "x-ratelimit-limit" => "120", "x-ratelimit-remaining" => "0" },
      )
      expect(error).to be_a(Nombaone::RateLimitError)
      expect(error.retry_after).to eq(17)
      expect(error.limit).to eq(120)
      expect(error.remaining).to eq(0)
    end

    it "degrades a non-JSON body (proxy page) to a typed error with a default code" do
      error = described_class.from_response(502, nil, {})
      expect(error).to be_a(Nombaone::ServerError)
      expect(error.code).to eq(Nombaone::ErrorCode::SYSTEM_UPSTREAM_ERROR)

      unknown = described_class.from_response(418, "I'm a teapot", {})
      expect(unknown).to be_a(described_class)
      expect(unknown.code).to eq(Nombaone::ErrorCode::SYSTEM_INTERNAL_ERROR)
    end

    it "tolerates an unknown future error code without breaking" do
      error = described_class.from_response(400, error_body(code: "SOME_FUTURE_CODE"), {})
      expect(error.code).to eq("SOME_FUTURE_CODE")
    end
  end

  describe Nombaone::ErrorCode do
    it "vendors the full public catalog as name=value constants" do
      expect(described_class::CUSTOMER_NOT_FOUND).to eq("CUSTOMER_NOT_FOUND")
      expect(described_class::ALL).to include("IDEMPOTENCY_IN_PROGRESS", "API_KEY_HOST_MISMATCH")
      expect(described_class::ALL.size).to eq(72)
    end
  end

  it "roots every SDK exception at Nombaone::Error" do
    expect(described_class.ancestors).to include(Nombaone::Error)
    expect(Nombaone::TimeoutError.ancestors).to include(Nombaone::ConnectionError, Nombaone::Error)
    expect(Nombaone::WebhookVerificationError.ancestors).to include(Nombaone::Error)
  end
end
