# frozen_string_literal: true

RSpec.describe "Idempotency keys" do
  def keys_from(mock)
    mock.calls.map { |call| call.headers["idempotency-key"] }
  end

  it "auto-generates a UUID Idempotency-Key on every POST" do
    mock = mock_connection
    mock.ok({})
    build_client(mock).request(method: :post, path: "/customers", body: { name: "Ada" })

    expect(keys_from(mock).first).to match(SpecSupport::ClientHelpers::UUID_PATTERN)
  end

  it "reuses the SAME key across automatic retries — the money-safety invariant" do
    mock = mock_connection
    mock.fail(500, code: "SYSTEM_INTERNAL_ERROR")
    mock.fail(503, code: "SYSTEM_UPSTREAM_ERROR")
    mock.ok({})

    build_client(mock).request(method: :post, path: "/subscriptions", body: {})

    keys = keys_from(mock)
    expect(keys.length).to eq(3)
    expect(keys.first).to match(SpecSupport::ClientHelpers::UUID_PATTERN)
    expect(keys.uniq.length).to eq(1)
  end

  it "generates a FRESH key for each separate logical call" do
    mock = mock_connection
    mock.ok({})
    mock.ok({})

    client = build_client(mock)
    client.request(method: :post, path: "/customers", body: {})
    client.request(method: :post, path: "/customers", body: {})

    first, second = keys_from(mock)
    expect(first).not_to eq(second)
  end

  it "honors an explicit idempotency_key (e.g. a payout's merchantTxRef)" do
    mock = mock_connection
    mock.ok({})

    build_client(mock).request(
      method: :post,
      path: "/settlements/payout",
      body: { amount_in_kobo: 100_000 },
      options: { idempotency_key: "payout-2026-07-05-001" },
    )

    expect(keys_from(mock).first).to eq("payout-2026-07-05-001")
  end

  it "does not attach a key to GET / PATCH / DELETE" do
    mock = mock_connection
    mock.ok({})
    mock.ok({})
    mock.ok({})

    client = build_client(mock)
    client.request(method: :get, path: "/customers")
    client.request(method: :patch, path: "/customers/x", body: {})
    client.request(method: :delete, path: "/customers/x/discount")

    expect(keys_from(mock)).to all(be_nil)
  end
end
