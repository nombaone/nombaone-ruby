# frozen_string_literal: true

require "securerandom"
require "socket"

# End-to-end suite against a real NombaOne API. Opt-in:
#
#   NOMBAONE_INTEGRATION=1 \
#   NOMBAONE_API_KEY=nbo_sandbox_… \
#   NOMBAONE_BASE_URL=https://sandbox.api.nombaone.xyz \
#   bundle exec rspec spec/integration
#
# The webhook round-trip registers a listener on 127.0.0.1, so it only runs when
# the target is a LOCAL API that can call back into it.
RSpec.describe "live sandbox integration", :integration, order: :defined do
  enabled = ENV["NOMBAONE_INTEGRATION"] == "1"
  base_url = ENV["NOMBAONE_BASE_URL"] || "https://sandbox.api.nombaone.xyz"
  local_target = base_url.match?(/localhost|127\.0\.0\.1/)
  unique = "sdk-it-#{SecureRandom.hex(6)}"

  before(:all) do
    skip "set NOMBAONE_INTEGRATION=1 to run the live suite" unless enabled

    @nombaone = Nombaone.new(ENV.fetch("NOMBAONE_API_KEY"), base_url: base_url)

    @customer = @nombaone.customers.create(email: "#{unique}@example.com", name: "SDK Integration")
    @plan = @nombaone.plans.create(name: "SDK IT #{unique}")
    @price = @nombaone.plans.prices.create(@plan.id, unit_amount_in_kobo: 250_000,
                                                     interval: "month")
    @method = @nombaone.sandbox.create_payment_method(customer_id: @customer.id,
                                                      behavior: "success")
    @subscription = @nombaone.subscriptions.create(
      customer_id: @customer.id, price_id: @price.id, payment_method_id: @method.id,
    )
  end

  it "creates a customer, plan, price, sandbox method, and an active subscription" do
    expect(@customer.id).to match(/\Anbo\d{12}cus\z/)
    expect(@customer.mode).to eq("sandbox")
    expect(@plan.status).to eq("active")
    expect(@price.unit_amount_in_kobo).to eq(250_000)
    expect(@price.currency).to eq("NGN")
    expect(@method.kind).to eq("card")
    expect(@subscription.id).to match(/\Anbo\d{12}sub\z/)
    expect(%w[active incomplete trialing]).to include(@subscription.status)
  end

  it "advances a billing cycle through the real engine (test clock)" do
    result = @nombaone.sandbox.advance_cycle(@subscription.id)
    expect(result.subscription_id).to eq(@subscription.id)
    expect(result.invoice.total_in_kobo).to be > 0
    expect(%w[paid past_due pending open]).to include(result.outcome)
  end

  it "previews the upcoming invoice and reads dunning state" do
    upcoming = @nombaone.subscriptions.retrieve_upcoming_invoice(@subscription.id)
    expect(upcoming.subscription_id).to eq(@subscription.id)
    expect(upcoming.amount_due_in_kobo).to be >= 0

    dunning = @nombaone.subscriptions.dunning.retrieve(@subscription.id)
    expect(dunning.subscription_ref).to eq(@subscription.id)
  end

  it "paginates with real cursors and auto-iteration" do
    page = @nombaone.customers.list(limit: 1)
    expect(page.data.length).to be <= 1
    expect(page.limit).to eq(1)
    expect(page.has_more?).to be(true).or be(false)

    count = 0
    @nombaone.customers.list(limit: 1).each do |_customer|
      count += 1
      break if count >= 3 # proves cursors thread without walking everything
    end
    expect(count).to be >= 1
  end

  it "replays the same idempotency key to the same resource" do
    key = "#{unique}-idem"
    params = { email: "#{unique}-idem@example.com", name: "Idem Test" }
    first = @nombaone.customers.create(**params, request_options: { idempotency_key: key })
    second = @nombaone.customers.create(**params, request_options: { idempotency_key: key })
    expect(second.id).to eq(first.id)
  end

  it "surfaces typed errors with code, hint, doc_url, and request_id" do
    missing = begin
      @nombaone.customers.retrieve("nbo000000000000cus")
    rescue Nombaone::NotFoundError => e
      e
    end
    expect(missing).to be_a(Nombaone::NotFoundError)
    expect(missing.code).to eq("CUSTOMER_NOT_FOUND")
    expect(missing.hint.length).to be > 0
    expect(missing.doc_url).to include("CUSTOMER_NOT_FOUND")
    expect(missing.request_id).to match(/\Areq_/)

    dup = begin
      @nombaone.customers.create(email: "#{unique}@example.com", name: "Dup")
    rescue Nombaone::ConflictError => e
      e
    end
    expect(dup).to be_a(Nombaone::ConflictError)
    expect(dup.code).to eq("CUSTOMER_EMAIL_TAKEN")
  end

  it "cancels the subscription cleanly" do
    canceled = @nombaone.subscriptions.cancel(@subscription.id, mode: "now")
    expect(canceled.status).to eq("canceled")
    expect(canceled.cancellation_reason).to eq("voluntary")
  end

  context "when the target is a local API (webhook round-trip)", if: local_target do
    it "delivers a simulated, signed event to a registered endpoint" do
      listener = SpecSupport::CaptureListener.new
      begin
        endpoint = @nombaone.webhook_endpoints.create(url: listener.url, enabled_events: ["*"])
        expect(endpoint.signing_secret.length).to be > 10

        @nombaone.sandbox.simulate_webhook(type: "invoice.paid",
                                           payload: { reference: "nbo000000000001inv" })

        delivery = listener.wait_for_delivery(timeout: 15)
        expect(delivery).not_to be_nil, "no delivery arrived within 15s"
        expect(delivery[:headers]["x-nombaone-event-type"]).to eq("invoice.paid")

        signature = delivery[:headers]["x-nombaone-signature"].to_s
        if signature.match?(/(^|,)\s*t=\d+/) && signature.include?("v1=")
          event = @nombaone.webhooks.construct_event(delivery[:body], signature,
                                                     endpoint.signing_secret)
          expect(event.type).to eq("invoice.paid")
        else
          warn "[integration] backend signature is not yet in the documented " \
               "\"t=…,v1=…\" format: #{signature[0, 32]}… — construct_event will verify " \
               "once the backend ships the docs scheme."
          expect(signature.length).to be > 0
        end
      ensure
        listener.close
      end
    end
  end
end
