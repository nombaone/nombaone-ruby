# frozen_string_literal: true

RSpec.describe "Catalog & billing resources" do
  let(:mock) { mock_connection }
  let(:client) { build_client(mock) }
  let(:id) { "nbo000000000001xxx" }

  def last = mock.calls.last

  def expect_wire(http_method, path)
    expect(last.http_method).to eq(http_method)
    expect(last.url).to eq("http://api.test/v1#{path}")
  end

  describe "plans" do
    it "create → POST /plans" do
      mock.ok({})
      client.plans.create(name: "Pro", description: "desc")
      expect_wire(:post, "/plans")
      expect(last.body).to eq("name" => "Pro", "description" => "desc")
    end

    it "retrieve → GET /plans/{id}" do
      mock.ok({})
      client.plans.retrieve(id)
      expect_wire(:get, "/plans/#{id}")
    end

    it "update → PATCH /plans/{id}, clearing description with an explicit nil" do
      mock.ok({})
      client.plans.update(id, description: nil)
      expect_wire(:patch, "/plans/#{id}")
      expect(last.body).to eq("description" => nil)
    end

    it "list → GET /plans?status=active" do
      mock.page([], has_more: false, next_cursor: nil)
      client.plans.list(status: "active")
      expect_wire(:get, "/plans?status=active")
    end

    it "archive → POST /plans/{id}/archive" do
      mock.ok({})
      client.plans.archive(id)
      expect_wire(:post, "/plans/#{id}/archive")
      expect(last.body).to eq({})
    end

    it "prices.create → POST /plans/{id}/prices with integer kobo" do
      mock.ok({})
      client.plans.prices.create(id, unit_amount_in_kobo: 250_000, interval: "month")
      expect_wire(:post, "/plans/#{id}/prices")
      expect(last.body).to eq("unitAmountInKobo" => 250_000, "interval" => "month")
      expect(last.headers["idempotency-key"]).to match(SpecSupport::ClientHelpers::UUID_PATTERN)
    end

    it "prices.list → GET /plans/{id}/prices" do
      mock.page([], has_more: false, next_cursor: nil)
      client.plans.prices.list(id)
      expect_wire(:get, "/plans/#{id}/prices")
    end
  end

  describe "prices" do
    it "retrieve → GET /prices/{id}" do
      mock.ok({})
      client.prices.retrieve(id)
      expect_wire(:get, "/prices/#{id}")
    end

    it "list → GET /prices?planRef=…&active=true (the wire filter is planRef)" do
      mock.page([], has_more: false, next_cursor: nil)
      client.prices.list(plan_ref: id, active: true)
      expect_wire(:get, "/prices?planRef=#{id}&active=true")
    end

    it "deactivate → POST /prices/{id}/deactivate" do
      mock.ok({})
      client.prices.deactivate(id)
      expect_wire(:post, "/prices/#{id}/deactivate")
      expect(last.body).to eq({})
    end
  end

  describe "subscriptions" do
    it "create → POST /subscriptions with an idempotency key" do
      mock.ok({})
      client.subscriptions.create(customer_id: id, price_id: id, payment_method_id: id)
      expect_wire(:post, "/subscriptions")
      expect(last.body).to eq("customerId" => id, "priceId" => id, "paymentMethodId" => id)
      expect(last.headers["idempotency-key"]).to match(SpecSupport::ClientHelpers::UUID_PATTERN)
    end

    it "retrieve → GET /subscriptions/{id}" do
      mock.ok({})
      client.subscriptions.retrieve(id)
      expect_wire(:get, "/subscriptions/#{id}")
    end

    it "update → PATCH /subscriptions/{id}" do
      mock.ok({})
      client.subscriptions.update(id, metadata: { tier: "gold" })
      expect_wire(:patch, "/subscriptions/#{id}")
      expect(last.body).to eq("metadata" => { "tier" => "gold" })
    end

    it "list → GET /subscriptions?customerId=…&status=… (the wire filter is customerId)" do
      mock.page([], has_more: false, next_cursor: nil)
      client.subscriptions.list(customer_id: id, status: "active")
      expect_wire(:get, "/subscriptions?customerId=#{id}&status=active")
    end

    it "list_events → GET /subscriptions/{id}/events" do
      mock.page([], has_more: false, next_cursor: nil)
      client.subscriptions.list_events(id)
      expect_wire(:get, "/subscriptions/#{id}/events")
    end

    it "pause → POST /subscriptions/{id}/pause with maxDays" do
      mock.ok({})
      client.subscriptions.pause(id, max_days: 14)
      expect_wire(:post, "/subscriptions/#{id}/pause")
      expect(last.body).to eq("maxDays" => 14)
    end

    it "pause with no arg sends an empty body" do
      mock.ok({})
      client.subscriptions.pause(id)
      expect(last.body).to eq({})
    end

    it "resume → POST /subscriptions/{id}/resume" do
      mock.ok({})
      client.subscriptions.resume(id)
      expect_wire(:post, "/subscriptions/#{id}/resume")
      expect(last.body).to eq({})
    end

    it "cancel → POST /subscriptions/{id}/cancel with mode" do
      mock.ok({})
      client.subscriptions.cancel(id, mode: "at_period_end")
      expect_wire(:post, "/subscriptions/#{id}/cancel")
      expect(last.body).to eq("mode" => "at_period_end")
    end

    it "resubscribe → POST /subscriptions/{id}/resubscribe" do
      mock.ok({})
      client.subscriptions.resubscribe(id)
      expect_wire(:post, "/subscriptions/#{id}/resubscribe")
    end

    it "change → POST /subscriptions/{id}/change" do
      mock.ok({})
      client.subscriptions.change(id, price_id: id)
      expect_wire(:post, "/subscriptions/#{id}/change")
      expect(last.body).to eq("priceId" => id)
    end

    it "update_payment_method → POST /subscriptions/{id}/payment-method" do
      mock.ok({})
      client.subscriptions.update_payment_method(id, checkout_token: "tok")
      expect_wire(:post, "/subscriptions/#{id}/payment-method")
      expect(last.body).to eq("checkoutToken" => "tok")
    end

    it "retrieve_upcoming_invoice → GET /subscriptions/{id}/upcoming-invoice" do
      mock.ok({})
      client.subscriptions.retrieve_upcoming_invoice(id)
      expect_wire(:get, "/subscriptions/#{id}/upcoming-invoice")
    end

    it "apply_discount → POST /subscriptions/{id}/discount" do
      mock.ok({})
      client.subscriptions.apply_discount(id, coupon: "LAUNCH20")
      expect_wire(:post, "/subscriptions/#{id}/discount")
      expect(last.body).to eq("coupon" => "LAUNCH20")
    end

    it "remove_discount → DELETE /subscriptions/{id}/discount" do
      mock.ok({})
      client.subscriptions.remove_discount(id)
      expect_wire(:delete, "/subscriptions/#{id}/discount")
    end

    it "schedule.create → POST /subscriptions/{id}/schedule" do
      mock.ok({})
      client.subscriptions.schedule.create(id, price_id: id)
      expect_wire(:post, "/subscriptions/#{id}/schedule")
      expect(last.body).to eq("priceId" => id)
    end

    it "schedule.retrieve → GET /subscriptions/{id}/schedule" do
      mock.ok({})
      client.subscriptions.schedule.retrieve(id)
      expect_wire(:get, "/subscriptions/#{id}/schedule")
    end

    it "schedule.release → DELETE /subscriptions/{id}/schedule" do
      mock.ok({})
      client.subscriptions.schedule.release(id)
      expect_wire(:delete, "/subscriptions/#{id}/schedule")
    end

    it "dunning.retrieve → GET /subscriptions/{id}/dunning" do
      mock.ok({})
      client.subscriptions.dunning.retrieve(id)
      expect_wire(:get, "/subscriptions/#{id}/dunning")
    end

    it "dunning.list_attempts → GET /subscriptions/{id}/dunning/attempts" do
      mock.page([], has_more: false, next_cursor: nil)
      client.subscriptions.dunning.list_attempts(id)
      expect_wire(:get, "/subscriptions/#{id}/dunning/attempts")
    end
  end

  describe "invoices" do
    it "retrieve → GET /invoices/{id}" do
      mock.ok({})
      client.invoices.retrieve(id)
      expect_wire(:get, "/invoices/#{id}")
    end

    it "list → GET /invoices?customerId=…&status=open" do
      mock.page([], has_more: false, next_cursor: nil)
      client.invoices.list(customer_id: id, status: "open")
      expect_wire(:get, "/invoices?customerId=#{id}&status=open")
    end

    it "void → POST /invoices/{id}/void" do
      mock.ok({})
      client.invoices.void(id, comment: "duplicate")
      expect_wire(:post, "/invoices/#{id}/void")
      expect(last.body).to eq("comment" => "duplicate")
    end
  end

  describe "coupons" do
    it "create → POST /coupons" do
      mock.ok({})
      client.coupons.create(code: "LAUNCH20", percent_off: 20, duration: "repeating",
                            duration_in_cycles: 3)
      expect_wire(:post, "/coupons")
      expect(last.body).to eq(
        "code" => "LAUNCH20", "percentOff" => 20, "duration" => "repeating",
        "durationInCycles" => 3
      )
    end

    it "retrieve → GET /coupons/{id}" do
      mock.ok({})
      client.coupons.retrieve(id)
      expect_wire(:get, "/coupons/#{id}")
    end

    it "update → PATCH /coupons/{id}" do
      mock.ok({})
      client.coupons.update(id, max_redemptions: 5)
      expect_wire(:patch, "/coupons/#{id}")
      expect(last.body).to eq("maxRedemptions" => 5)
    end

    it "list → GET /coupons" do
      mock.page([], has_more: false, next_cursor: nil)
      client.coupons.list
      expect_wire(:get, "/coupons")
    end
  end
end
