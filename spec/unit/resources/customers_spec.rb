# frozen_string_literal: true

RSpec.describe Nombaone::Resources::Customers do
  let(:mock) { mock_connection }
  let(:client) { build_client(mock) }
  let(:cus) { "nbo000000000001cus" }
  let(:crg) { "nbo000000000002crg" }

  def last_call
    mock.calls.last
  end

  it "create → POST /v1/customers with a camelCase body and an idempotency key" do
    mock.ok({ "id" => cus, "email" => "a@b.co" })
    result = client.customers.create(email: "a@b.co", name: "Ada", metadata: { crm_id: "x" })

    expect(last_call.http_method).to eq(:post)
    expect(last_call.url).to eq("http://api.test/v1/customers")
    expect(last_call.body).to eq(
      "email" => "a@b.co", "name" => "Ada", "metadata" => { "crm_id" => "x" },
    )
    expect(last_call.headers["idempotency-key"]).to match(SpecSupport::ClientHelpers::UUID_PATTERN)
    expect(result).to be_a(Nombaone::NombaObject)
    expect(result.id).to eq(cus)
  end

  it "create omits unset optional fields" do
    mock.ok({})
    client.customers.create(email: "a@b.co", name: "Ada")
    expect(last_call.body).to eq("email" => "a@b.co", "name" => "Ada")
  end

  it "retrieve → GET /v1/customers/{id}, encoding the id" do
    mock.ok({ "id" => cus })
    client.customers.retrieve(cus)
    expect(last_call.http_method).to eq(:get)
    expect(last_call.url).to eq("http://api.test/v1/customers/#{cus}")
    expect(last_call.headers).not_to have_key("idempotency-key")
  end

  it "update → PATCH, keeping an explicit nil phone to clear it" do
    mock.ok({})
    client.customers.update(cus, phone: nil)
    expect(last_call.http_method).to eq(:patch)
    expect(last_call.url).to eq("http://api.test/v1/customers/#{cus}")
    expect(last_call.body).to eq("phone" => nil)
  end

  it "list → GET /v1/customers with camelCase query filters" do
    mock.page([], has_more: false, next_cursor: nil)
    page = client.customers.list(email: "a@b.co", limit: 50)
    expect(last_call.http_method).to eq(:get)
    expect(last_call.url).to eq("http://api.test/v1/customers?email=a%40b.co&limit=50")
    expect(page).to be_a(Nombaone::Page)
  end

  it "apply_discount → POST /v1/customers/{id}/discount" do
    mock.ok({ "domain" => "discount" })
    client.customers.apply_discount(cus, coupon: "LAUNCH20")
    expect(last_call.http_method).to eq(:post)
    expect(last_call.url).to eq("http://api.test/v1/customers/#{cus}/discount")
    expect(last_call.body).to eq("coupon" => "LAUNCH20")
  end

  it "remove_discount → DELETE /v1/customers/{id}/discount" do
    mock.ok({})
    client.customers.remove_discount(cus)
    expect(last_call.http_method).to eq(:delete)
    expect(last_call.url).to eq("http://api.test/v1/customers/#{cus}/discount")
    expect(last_call.body).to be_nil
  end

  it "grant_credit → POST /v1/customers/{id}/credit with integer kobo" do
    mock.ok({ "domain" => "credit_grant" })
    client.customers.grant_credit(cus, amount_in_kobo: 250_000, source: "goodwill")
    expect(last_call.http_method).to eq(:post)
    expect(last_call.url).to eq("http://api.test/v1/customers/#{cus}/credit")
    expect(last_call.body).to eq("amountInKobo" => 250_000, "source" => "goodwill")
    expect(last_call.body["amountInKobo"]).to be_a(Integer)
    expect(last_call.headers["idempotency-key"]).to match(SpecSupport::ClientHelpers::UUID_PATTERN)
  end

  it "retrieve_credit_balance → GET /v1/customers/{id}/credit" do
    mock.ok({ "balanceInKobo" => 0 })
    result = client.customers.retrieve_credit_balance(cus)
    expect(last_call.http_method).to eq(:get)
    expect(last_call.url).to eq("http://api.test/v1/customers/#{cus}/credit")
    expect(result.balance_in_kobo).to eq(0)
  end

  it "void_credit → DELETE /v1/customers/{id}/credit/{grantId}" do
    mock.ok({})
    client.customers.void_credit(cus, crg)
    expect(last_call.http_method).to eq(:delete)
    expect(last_call.url).to eq("http://api.test/v1/customers/#{cus}/credit/#{crg}")
  end

  it "threads a per-call idempotency_key and headers" do
    mock.ok({})
    client.customers.create(
      email: "a@b.co", name: "Ada",
      request_options: { idempotency_key: "cust-123", headers: { "X-Trace" => "t" } }
    )
    expect(last_call.headers["idempotency-key"]).to eq("cust-123")
    expect(last_call.headers["x-trace"]).to eq("t")
  end
end
