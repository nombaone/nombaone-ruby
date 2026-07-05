# frozen_string_literal: true

require "json"

# The drift alarm. Every SDK method is exercised against a recording transport;
# each emitted `METHOD /v1/path` must exist in the committed OpenAPI snapshot
# (spec/openapi.json), and every spec operation (minus the explicit exclusions)
# must be emitted by some SDK method. Either direction failing names the route.
module OpenAPIConformance
  HTTP_METHODS = %w[get post patch put delete].freeze

  SPEC = JSON.parse(File.read(File.expand_path("../../spec/openapi.json", __dir__))).freeze

  SPEC_OPS = SPEC.fetch("paths").flat_map do |path, item|
    item.keys.select { |m| HTTP_METHODS.include?(m) }.map do |method|
      { method: method, segments: path.split("/").reject(&:empty?), key: "#{method} #{path}" }
    end
  end.freeze

  # Routes intentionally NOT in the SDK surface.
  EXCLUDED = [
    "get /v1/health",         # infra liveness, not a billing call
    "get /v1/openapi.json",   # the spec itself
    "post /v1/examples",      # deletable reference scaffold
    "get /v1/examples",
    "get /v1/examples/{id}",
  ].freeze

  ID = "nbo000000000001xxx"
  GRANT = "nbo000000000002crg"
  DELIVERY = "nbo000000000003whd"

  module_function

  # Most-specific structural match: `{param}` matches any segment; literals win ties.
  def match_spec_op(method, url_path)
    segments = url_path.split("/").reject(&:empty?)
    best = nil
    best_literals = -1
    SPEC_OPS.each do |op|
      next unless op[:method] == method && op[:segments].length == segments.length

      literals = literal_match_count(op[:segments], segments)
      next if literals.nil?

      if literals > best_literals
        best = op
        best_literals = literals
      end
    end
    best
  end

  # Count literal (non-`{param}`) segments that match; nil if any literal differs.
  def literal_match_count(spec_segments, segments)
    literals = 0
    spec_segments.each_with_index do |spec_seg, i|
      next if spec_seg.start_with?("{")
      return nil unless spec_seg == segments[i]

      literals += 1
    end
    literals
  end

  # One entry per SDK method — the complete public surface.
  def exercises(client) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    mandate = {
      customer_ref: ID, customer_account_number: "0123456789", bank_code: "058",
      customer_name: "A", customer_account_name: "A", customer_phone_number: "+234",
      customer_address: "Lagos", narration: "sub", max_amount_in_kobo: 100
    }
    [
      # customers (9)
      -> { client.customers.create(email: "a@b.co", name: "A") },
      -> { client.customers.retrieve(ID) },
      -> { client.customers.update(ID, name: "B") },
      -> { client.customers.list },
      -> { client.customers.apply_discount(ID, coupon: "X") },
      -> { client.customers.remove_discount(ID) },
      -> { client.customers.grant_credit(ID, amount_in_kobo: 100) },
      -> { client.customers.retrieve_credit_balance(ID) },
      -> { client.customers.void_credit(ID, GRANT) },
      # plans (+ nested prices) (7)
      -> { client.plans.create(name: "Pro") },
      -> { client.plans.retrieve(ID) },
      -> { client.plans.update(ID, name: "Pro2") },
      -> { client.plans.list },
      -> { client.plans.archive(ID) },
      -> { client.plans.prices.create(ID, unit_amount_in_kobo: 100, interval: "month") },
      -> { client.plans.prices.list(ID) },
      # prices (3)
      -> { client.prices.retrieve(ID) },
      -> { client.prices.list },
      -> { client.prices.deactivate(ID) },
      # subscriptions (+ schedule + dunning) (19)
      -> { client.subscriptions.create(customer_id: ID, price_id: ID, payment_method_id: ID) },
      -> { client.subscriptions.retrieve(ID) },
      -> { client.subscriptions.update(ID, metadata: {}) },
      -> { client.subscriptions.list },
      -> { client.subscriptions.list_events(ID) },
      -> { client.subscriptions.pause(ID) },
      -> { client.subscriptions.resume(ID) },
      -> { client.subscriptions.cancel(ID) },
      -> { client.subscriptions.resubscribe(ID) },
      -> { client.subscriptions.change(ID, price_id: ID) },
      -> { client.subscriptions.update_payment_method(ID, checkout_token: "t") },
      -> { client.subscriptions.retrieve_upcoming_invoice(ID) },
      -> { client.subscriptions.apply_discount(ID, coupon: "X") },
      -> { client.subscriptions.remove_discount(ID) },
      -> { client.subscriptions.schedule.create(ID, price_id: ID) },
      -> { client.subscriptions.schedule.retrieve(ID) },
      -> { client.subscriptions.schedule.release(ID) },
      -> { client.subscriptions.dunning.retrieve(ID) },
      -> { client.subscriptions.dunning.list_attempts(ID) },
      # invoices (3)
      -> { client.invoices.retrieve(ID) },
      -> { client.invoices.list },
      -> { client.invoices.void(ID) },
      # coupons (4)
      -> { client.coupons.create(code: "X", percent_off: 10, duration: "once") },
      -> { client.coupons.retrieve(ID) },
      -> { client.coupons.update(ID, max_redemptions: 5) },
      -> { client.coupons.list },
      # payment methods (6)
      lambda {
        client.payment_methods.setup(customer_ref: ID, amount_in_kobo: 100,
                                     callback_url: "https://x.co")
      },
      -> { client.payment_methods.create_virtual_account(customer_ref: ID) },
      -> { client.payment_methods.retrieve(ID) },
      -> { client.payment_methods.list },
      -> { client.payment_methods.set_default(ID) },
      -> { client.payment_methods.remove(ID) },
      # mandates (2)
      -> { client.mandates.create(**mandate) },
      -> { client.mandates.retrieve(ID) },
      # settlements (5)
      -> { client.settlements.retrieve(ID) },
      -> { client.settlements.list },
      -> { client.settlements.retrieve_escrow },
      -> { client.settlements.refund(ID) },
      lambda {
        client.settlements.create_payout(amount_in_kobo: 100, bank_code: "058",
                                         account_number: "01")
      },
      # webhook endpoints (+ deliveries) (9)
      -> { client.webhook_endpoints.create(url: "https://x.co/h") },
      -> { client.webhook_endpoints.retrieve(ID) },
      -> { client.webhook_endpoints.update(ID, disabled: true) },
      -> { client.webhook_endpoints.list },
      -> { client.webhook_endpoints.delete(ID) },
      -> { client.webhook_endpoints.rotate_secret(ID) },
      -> { client.webhook_endpoints.deliveries.list(ID) },
      -> { client.webhook_endpoints.deliveries.retrieve(ID, DELIVERY) },
      -> { client.webhook_endpoints.deliveries.replay(ID, DELIVERY) },
      # events (3)
      -> { client.events.list },
      -> { client.events.retrieve(ID) },
      -> { client.events.catalog },
      # organization (+ billing) (4)
      -> { client.organization.retrieve },
      -> { client.organization.update(settlement_mode: "split_at_collection") },
      -> { client.organization.billing.retrieve },
      -> { client.organization.billing.update(comms_enabled: true) },
      # metrics (1)
      -> { client.metrics.billing },
      # sandbox (3)
      -> { client.sandbox.create_payment_method(customer_id: ID) },
      -> { client.sandbox.advance_cycle(ID) },
      -> { client.sandbox.simulate_webhook(type: "invoice.paid") },
    ]
  end
end

RSpec.describe "OpenAPI conformance" do
  it "maps every SDK call to a spec operation, and covers every spec operation" do
    recorder = SpecSupport::RecordingConnection.new
    client = Nombaone.new("nbo_sandbox_conformance", base_url: "http://api.test",
                                                     http: recorder, max_retries: 0)

    OpenAPIConformance.exercises(client).each(&:call)

    covered = []
    unmatched = []
    recorder.calls.each do |call|
      match = OpenAPIConformance.match_spec_op(call.http_method.to_s, call.path)
      match ? covered << match[:key] : unmatched << "#{call.http_method} #{call.path}"
    end

    expect(unmatched).to eq([]), "SDK emitted routes that do not exist in the spec"

    missing = OpenAPIConformance::SPEC_OPS.map { |op| op[:key] }
                                          .reject do |key|
                                            OpenAPIConformance::EXCLUDED.include?(key) ||
                                              covered.include?(key)
                                          end
                                          .sort
    expect(missing).to eq([]), "spec operations with no SDK method exercising them"

    # Belt-and-braces: every EXCLUDED entry must really exist, so a renamed route
    # can't silently hide behind the exclusion list.
    OpenAPIConformance::EXCLUDED.each do |excluded|
      expect(OpenAPIConformance::SPEC_OPS.any? { |op| op[:key] == excluded })
        .to be(true), "EXCLUDED entry no longer exists in spec: #{excluded}"
    end
  end
end
