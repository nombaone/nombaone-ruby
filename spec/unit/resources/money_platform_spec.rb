# frozen_string_literal: true

RSpec.describe "Money & platform resources" do
  let(:mock) { mock_connection }
  let(:client) { build_client(mock) }
  let(:id) { "nbo000000000001xxx" }
  let(:whd) { "nbo000000000003whd" }

  def last = mock.calls.last

  def expect_wire(http_method, path)
    expect(last.http_method).to eq(http_method)
    expect(last.url).to eq("http://api.test/v1#{path}")
  end

  describe "payment_methods" do
    it "setup → POST /payment-methods/setup" do
      mock.ok({})
      client.payment_methods.setup(customer_ref: id, amount_in_kobo: 5_000,
                                   callback_url: "https://x.co")
      expect_wire(:post, "/payment-methods/setup")
      expect(last.body).to eq(
        "customerRef" => id, "amountInKobo" => 5_000, "callbackUrl" => "https://x.co",
      )
    end

    it "create_virtual_account → POST /payment-methods/virtual-account" do
      mock.ok({})
      client.payment_methods.create_virtual_account(customer_ref: id)
      expect_wire(:post, "/payment-methods/virtual-account")
      expect(last.body).to eq("customerRef" => id)
    end

    it "retrieve → GET /payment-methods/{id}" do
      mock.ok({})
      client.payment_methods.retrieve(id)
      expect_wire(:get, "/payment-methods/#{id}")
    end

    it "list → GET /payment-methods?customerRef=… (the wire filter is customerRef)" do
      mock.page([], has_more: false, next_cursor: nil)
      client.payment_methods.list(customer_ref: id)
      expect_wire(:get, "/payment-methods?customerRef=#{id}")
    end

    it "set_default → POST /payment-methods/{id}/default" do
      mock.ok({})
      client.payment_methods.set_default(id)
      expect_wire(:post, "/payment-methods/#{id}/default")
    end

    it "remove → DELETE /payment-methods/{id}" do
      mock.ok({})
      client.payment_methods.remove(id)
      expect_wire(:delete, "/payment-methods/#{id}")
    end
  end

  describe "mandates" do
    it "create → POST /mandates with an idempotency key" do
      mock.ok({})
      client.mandates.create(
        customer_ref: id, customer_account_number: "0123456789", bank_code: "058",
        customer_name: "Ada", customer_account_name: "Ada", customer_phone_number: "+234",
        customer_address: "Lagos", narration: "sub", max_amount_in_kobo: 500_000
      )
      expect_wire(:post, "/mandates")
      expect(last.body).to include("customerRef" => id, "bankCode" => "058",
                                   "maxAmountInKobo" => 500_000)
      expect(last.headers["idempotency-key"]).to match(SpecSupport::ClientHelpers::UUID_PATTERN)
    end

    it "retrieve → GET /mandates/{id}" do
      mock.ok({})
      client.mandates.retrieve(id)
      expect_wire(:get, "/mandates/#{id}")
    end
  end

  describe "settlements" do
    it "retrieve → GET /settlements/{id}" do
      mock.ok({})
      client.settlements.retrieve(id)
      expect_wire(:get, "/settlements/#{id}")
    end

    it "list → GET /settlements" do
      mock.page([], has_more: false, next_cursor: nil)
      client.settlements.list(status: "settled")
      expect_wire(:get, "/settlements?status=settled")
    end

    it "retrieve_escrow → GET /settlements/escrow (literal beats /settlements/{id})" do
      mock.ok({})
      client.settlements.retrieve_escrow
      expect_wire(:get, "/settlements/escrow")
    end

    it "refund → POST /settlements/{id}/refund" do
      mock.ok({})
      client.settlements.refund(id, amount_in_kobo: 100_000)
      expect_wire(:post, "/settlements/#{id}/refund")
      expect(last.body).to eq("amountInKobo" => 100_000)
    end

    it "create_payout → POST /settlements/payout, honoring a stable idempotency key" do
      mock.ok({})
      client.settlements.create_payout(
        amount_in_kobo: 5_000_000, bank_code: "058", account_number: "0123456789",
        request_options: { idempotency_key: "payout-42" }
      )
      expect_wire(:post, "/settlements/payout")
      expect(last.body).to eq(
        "amountInKobo" => 5_000_000, "bankCode" => "058", "accountNumber" => "0123456789",
      )
      expect(last.headers["idempotency-key"]).to eq("payout-42")
    end
  end

  describe "webhook_endpoints" do
    it "create → POST /webhooks" do
      mock.ok({})
      client.webhook_endpoints.create(url: "https://x.co/h", enabled_events: ["invoice.paid"])
      expect_wire(:post, "/webhooks")
      expect(last.body).to eq("url" => "https://x.co/h", "enabledEvents" => ["invoice.paid"])
    end

    it "retrieve → GET /webhooks/{id}" do
      mock.ok({})
      client.webhook_endpoints.retrieve(id)
      expect_wire(:get, "/webhooks/#{id}")
    end

    it "update → PATCH /webhooks/{id}" do
      mock.ok({})
      client.webhook_endpoints.update(id, disabled: true)
      expect_wire(:patch, "/webhooks/#{id}")
      expect(last.body).to eq("disabled" => true)
    end

    it "list → GET /webhooks" do
      mock.page([], has_more: false, next_cursor: nil)
      client.webhook_endpoints.list
      expect_wire(:get, "/webhooks")
    end

    it "delete → DELETE /webhooks/{id}" do
      mock.ok({})
      client.webhook_endpoints.delete(id)
      expect_wire(:delete, "/webhooks/#{id}")
    end

    it "rotate_secret → POST /webhooks/{id}/rotate-secret" do
      mock.ok({})
      client.webhook_endpoints.rotate_secret(id)
      expect_wire(:post, "/webhooks/#{id}/rotate-secret")
    end

    it "deliveries.list → GET /webhooks/{id}/deliveries" do
      mock.page([], has_more: false, next_cursor: nil)
      client.webhook_endpoints.deliveries.list(id, status: "dead")
      expect_wire(:get, "/webhooks/#{id}/deliveries?status=dead")
    end

    it "deliveries.retrieve → GET /webhooks/{id}/deliveries/{deliveryId}" do
      mock.ok({})
      client.webhook_endpoints.deliveries.retrieve(id, whd)
      expect_wire(:get, "/webhooks/#{id}/deliveries/#{whd}")
    end

    it "deliveries.replay → POST /webhooks/{id}/deliveries/{deliveryId}/replay" do
      mock.ok({})
      client.webhook_endpoints.deliveries.replay(id, whd)
      expect_wire(:post, "/webhooks/#{id}/deliveries/#{whd}/replay")
    end
  end

  describe "events" do
    it "list → GET /events" do
      mock.page([], has_more: false, next_cursor: nil)
      client.events.list(type: "invoice.paid")
      expect_wire(:get, "/events?type=invoice.paid")
    end

    it "retrieve → GET /events/{id}" do
      mock.ok({})
      client.events.retrieve(id)
      expect_wire(:get, "/events/#{id}")
    end

    it "catalog → GET /events/catalog" do
      mock.ok({})
      client.events.catalog
      expect_wire(:get, "/events/catalog")
    end
  end

  describe "organization" do
    it "retrieve → GET /organization" do
      mock.ok({})
      client.organization.retrieve
      expect_wire(:get, "/organization")
    end

    it "update → PUT /organization" do
      mock.ok({})
      client.organization.update(settlement_mode: "split_at_collection")
      expect_wire(:put, "/organization")
      expect(last.body).to eq("settlementMode" => "split_at_collection")
    end

    it "billing.retrieve → GET /organization/billing" do
      mock.ok({})
      client.organization.billing.retrieve
      expect_wire(:get, "/organization/billing")
    end

    it "billing.update → PUT /organization/billing with array policy fields" do
      mock.ok({})
      client.organization.billing.update(payday_bias_enabled: true, payday_days: [25, 28, 30])
      expect_wire(:put, "/organization/billing")
      expect(last.body).to eq("paydayBiasEnabled" => true, "paydayDays" => [25, 28, 30])
    end
  end

  describe "metrics" do
    it "billing → GET /metrics/billing" do
      mock.ok({})
      client.metrics.billing(from: "2026-06-01T00:00:00Z")
      expect_wire(:get, "/metrics/billing?from=2026-06-01T00%3A00%3A00Z")
    end
  end

  describe "sandbox" do
    it "create_payment_method → POST /sandbox/payment-methods" do
      mock.ok({})
      client.sandbox.create_payment_method(customer_id: id, behavior: "decline_insufficient_funds")
      expect_wire(:post, "/sandbox/payment-methods")
      expect(last.body).to eq("customerId" => id, "behavior" => "decline_insufficient_funds")
    end

    it "advance_cycle → POST /sandbox/subscriptions/{id}/advance-cycle" do
      mock.ok({})
      client.sandbox.advance_cycle(id)
      expect_wire(:post, "/sandbox/subscriptions/#{id}/advance-cycle")
    end

    it "simulate_webhook → POST /sandbox/webhooks/simulate, passing payload verbatim" do
      mock.ok({})
      client.sandbox.simulate_webhook(type: "invoice.paid", payload: { reference: id })
      expect_wire(:post, "/sandbox/webhooks/simulate")
      expect(last.body).to eq("type" => "invoice.paid", "payload" => { "reference" => id })
    end

    it "raises locally with a live key, before any network call" do
      live = Nombaone.new("nbo_live_x", http: mock, sleeper: ->(_s) {})
      expect { live.sandbox.advance_cycle(id) }
        .to raise_error(Nombaone::Error, /sandbox key/)
      expect(mock.calls).to be_empty
    end
  end
end
