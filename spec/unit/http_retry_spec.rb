# frozen_string_literal: true

RSpec.describe "Retry semantics" do
  it "retries a 500 and succeeds on the next attempt" do
    mock = mock_connection
    mock.fail(500, code: "SYSTEM_INTERNAL_ERROR")
    mock.ok({ "recovered" => true })

    result = build_client(mock).request(method: :get, path: "/customers")
    expect(result.recovered).to be(true)
    expect(mock.calls.length).to eq(2)
  end

  it "honors Retry-After on 429 and retries" do
    mock = mock_connection
    mock.fail(429, code: "RATE_LIMIT_EXCEEDED", headers: { "retry-after" => "0" })
    mock.ok({ "fine" => true })

    build_client(mock).request(method: :get, path: "/customers")
    expect(mock.calls.length).to eq(2)
  end

  it "gives up after max_retries and raises the typed error" do
    mock = mock_connection
    mock.fail(500, code: "SYSTEM_INTERNAL_ERROR")
    mock.fail(500, code: "SYSTEM_INTERNAL_ERROR")

    expect { build_client(mock, max_retries: 1).request(method: :get, path: "/customers") }
      .to raise_error(Nombaone::ServerError)
    expect(mock.calls.length).to eq(2)
  end

  it "exposes rate-limit details when 429 retries are exhausted" do
    mock = mock_connection
    mock.fail(429, code: "RATE_LIMIT_EXCEEDED", headers: {
                "retry-after" => "17",
                "x-ratelimit-limit" => "120",
                "x-ratelimit-remaining" => "0",
              })

    error = nil
    begin
      build_client(mock, max_retries: 0).request(method: :get, path: "/customers")
    rescue Nombaone::RateLimitError => e
      error = e
    end
    expect(error).to be_a(Nombaone::RateLimitError)
    expect(error.retry_after).to eq(17)
    expect(error.limit).to eq(120)
    expect(error.remaining).to eq(0)
  end

  it "does not retry a 4xx such as 422" do
    mock = mock_connection
    mock.fail(422, code: "CLIENT_VALIDATION_FAILED", fields: { "email" => ["Invalid email"] })

    expect { build_client(mock).request(method: :post, path: "/customers", body: {}) }
      .to raise_error(Nombaone::ValidationError)
    expect(mock.calls.length).to eq(1)
  end

  it "retries a 409 IDEMPOTENCY_IN_PROGRESS (our own in-flight attempt)" do
    mock = mock_connection
    mock.fail(409, code: "IDEMPOTENCY_IN_PROGRESS")
    mock.ok({ "settled" => true })

    build_client(mock).request(method: :post, path: "/subscriptions", body: {})
    expect(mock.calls.length).to eq(2)
  end

  it "does not retry other 409 conflicts" do
    mock = mock_connection
    mock.fail(409, code: "CLIENT_CONFLICT")

    expect { build_client(mock).request(method: :post, path: "/subscriptions", body: {}) }
      .to raise_error(Nombaone::ConflictError) { |e| expect(e.code).to eq("CLIENT_CONFLICT") }
    expect(mock.calls.length).to eq(1)
  end

  it "retries connection failures" do
    mock = mock_connection
    mock.network_error
    mock.ok({ "back" => true })

    build_client(mock).request(method: :get, path: "/customers")
    expect(mock.calls.length).to eq(2)
  end

  it "retries timeouts" do
    mock = mock_connection
    mock.timeout_error
    mock.ok({ "back" => true })

    build_client(mock).request(method: :get, path: "/customers")
    expect(mock.calls.length).to eq(2)
  end

  it "raises ConnectionError when the network never recovers" do
    mock = mock_connection
    mock.network_error
    mock.network_error

    expect { build_client(mock, max_retries: 1).request(method: :get, path: "/customers") }
      .to raise_error(Nombaone::ConnectionError)
    expect(mock.calls.length).to eq(2)
  end

  it "never retries a caller-initiated cancellation" do
    mock = mock_connection
    mock.ok({})

    expect do
      build_client(mock).request(
        method: :get, path: "/customers", options: { cancel_when: -> { true } },
      )
    end.to raise_error(Nombaone::ConnectionError, /canceled/)
    expect(mock.calls.length).to eq(0)
  end
end
