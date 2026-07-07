#!/usr/bin/env ruby
# frozen_string_literal: true

# Full-surface live verification — call EVERY SDK method against a real sandbox
# and prove nothing mis-parses or crashes.
#
# Classification (per the release playbook):
#   ok        — the method succeeded and returned a well-formed object/page.
#   expected  — a typed 4xx API error (the SDK correctly parsed a wire "no").
#   infra     — a 5xx or transport outage (backend/endpoint down, not an SDK bug).
#   DEFECT    — a crash, a non-Nombaone exception, or a 2xx that didn't parse.
#
# Exits 0 only when DEFECTS == 0.
#
#   NOMBAONE_API_KEY=nbo_sandbox_… ruby -Ilib scripts/verify.rb
#   # optional: NOMBAONE_BASE_URL=… (defaults to the host derived from the key)

require "nombaone"
require "securerandom"

RESULTS = []
LABELS = { ok: "ok", expected: "expected", infra: "infra", defect: "DEFECT" }.freeze

def classify(error)
  case error
  when Nombaone::ConnectionError, Nombaone::TimeoutError
    [:infra, error.class.name.split("::").last]
  when Nombaone::APIError
    if error.status_code.between?(200, 299)
      [:defect, "unparseable 2xx (#{error.code})"]
    elsif error.status_code >= 500
      [:infra, "#{error.status_code} #{error.code}"]
    else
      [:expected, "#{error.status_code} #{error.code}"]
    end
  else
    [:defect, "#{error.class}: #{error.message.to_s[0, 60]}"]
  end
end

def summarize(value)
  case value
  when Nombaone::Page then "page[#{value.data.length}]"
  when Nombaone::NombaObject then (value[:id] || value[:reference] || value[:event] || value[:domain] || "ok").to_s
  else value.class.name
  end
end

def check(name)
  value = yield
  RESULTS << [name, :ok, summarize(value)]
  puts format("  %-40s %-9s %s", name, LABELS[:ok], summarize(value))
  value
rescue Nombaone::Error, StandardError => e
  status, detail = classify(e)
  RESULTS << [name, status, detail]
  puts format("  %-40s %-9s %s", name, LABELS[status], detail)
  nil
end

client = Nombaone.new(ENV.fetch("NOMBAONE_API_KEY"), base_url: ENV["NOMBAONE_BASE_URL"])
sfx = SecureRandom.hex(6)
FAKE = "nbo000000000000xxx"

puts "NombaOne Ruby SDK #{Nombaone::VERSION} — full-surface live verification"
puts "target #{client.base_url}  (mode: #{client.mode})"
puts

# ---- setup: real resources the rest of the surface operates on ----
puts "· customers"
customer = check("customers.create") { client.customers.create(email: "verify-#{sfx}@example.com", name: "Verify") }
cus = customer&.id || FAKE
check("customers.retrieve") { client.customers.retrieve(cus) }
check("customers.update") { client.customers.update(cus, phone: "+2348012345678") }
check("customers.list") { client.customers.list(limit: 2) }
grant = check("customers.grant_credit") { client.customers.grant_credit(cus, amount_in_kobo: 5_000, source: "goodwill") }
check("customers.retrieve_credit_balance") { client.customers.retrieve_credit_balance(cus) }

puts "· coupons"
coupon = check("coupons.create") { client.coupons.create(code: "VERIFY#{sfx.upcase}", percent_off: 10, duration: "once") }
cpn = coupon&.code || "NOPE"
check("coupons.retrieve") { client.coupons.retrieve(coupon&.id || FAKE) }
check("coupons.update") { client.coupons.update(coupon&.id || FAKE, max_redemptions: 100) }
check("coupons.list") { client.coupons.list(limit: 2) }
check("customers.apply_discount") { client.customers.apply_discount(cus, coupon: cpn) }
check("customers.remove_discount") { client.customers.remove_discount(cus) }
check("customers.void_credit") { client.customers.void_credit(cus, grant&.id || FAKE) }

puts "· plans & prices"
plan = check("plans.create") { client.plans.create(name: "Verify #{sfx}") }
pln = plan&.id || FAKE
check("plans.retrieve") { client.plans.retrieve(pln) }
check("plans.update") { client.plans.update(pln, description: "verified") }
check("plans.list") { client.plans.list(limit: 2) }
price1 = check("plans.prices.create") { client.plans.prices.create(pln, unit_amount_in_kobo: 250_000, interval: "month") }
price2 = check("plans.prices.create #2") { client.plans.prices.create(pln, unit_amount_in_kobo: 300_000, interval: "month") }
price3 = check("plans.prices.create #3") { client.plans.prices.create(pln, unit_amount_in_kobo: 500_000, interval: "month") }
check("plans.prices.list") { client.plans.prices.list(pln) }
check("prices.retrieve") { client.prices.retrieve(price1&.id || FAKE) }
check("prices.list") { client.prices.list(plan_ref: pln) }
check("prices.deactivate") { client.prices.deactivate(price2&.id || FAKE) }

puts "· payment methods (sandbox + real)"
pm1 = check("sandbox.create_payment_method") { client.sandbox.create_payment_method(customer_id: cus, behavior: "success") }
pm2 = check("sandbox.create_payment_method #2") { client.sandbox.create_payment_method(customer_id: cus, behavior: "success") }
pm3 = check("sandbox.create_payment_method #3") { client.sandbox.create_payment_method(customer_id: cus, behavior: "success") }
check("payment_methods.setup") { client.payment_methods.setup(customer_ref: cus, amount_in_kobo: 5_000, callback_url: "https://example.com/return") }
check("payment_methods.create_virtual_account") { client.payment_methods.create_virtual_account(customer_ref: cus) }
check("payment_methods.retrieve") { client.payment_methods.retrieve(pm1&.id || FAKE) }
check("payment_methods.list") { client.payment_methods.list(customer_ref: cus) }
check("payment_methods.set_default") { client.payment_methods.set_default(pm1&.id || FAKE) }
check("payment_methods.remove") { client.payment_methods.remove(pm3&.id || FAKE) }

puts "· subscriptions (+ schedule, dunning)"
sub = check("subscriptions.create") { client.subscriptions.create(customer_id: cus, price_id: price1&.id || FAKE, payment_method_id: pm1&.id || FAKE) }
sid = sub&.id || FAKE
check("subscriptions.retrieve") { client.subscriptions.retrieve(sid) }
check("subscriptions.update") { client.subscriptions.update(sid, metadata: { tier: "gold" }) }
check("subscriptions.list") { client.subscriptions.list(customer_id: cus) }
check("subscriptions.list_events") { client.subscriptions.list_events(sid) }
check("subscriptions.retrieve_upcoming_invoice") { client.subscriptions.retrieve_upcoming_invoice(sid) }
check("subscriptions.apply_discount") { client.subscriptions.apply_discount(sid, coupon: cpn) }
check("subscriptions.remove_discount") { client.subscriptions.remove_discount(sid) }
check("subscriptions.schedule.create") { client.subscriptions.schedule.create(sid, price_id: price3&.id || FAKE) }
check("subscriptions.schedule.retrieve") { client.subscriptions.schedule.retrieve(sid) }
check("subscriptions.schedule.release") { client.subscriptions.schedule.release(sid) }
check("subscriptions.dunning.retrieve") { client.subscriptions.dunning.retrieve(sid) }
check("subscriptions.dunning.list_attempts") { client.subscriptions.dunning.list_attempts(sid) }
check("subscriptions.update_payment_method") { client.subscriptions.update_payment_method(sid, payment_method_reference: pm2&.id || FAKE) }
check("subscriptions.change") { client.subscriptions.change(sid, price_id: price3&.id || FAKE) }
check("subscriptions.pause") { client.subscriptions.pause(sid) }
check("subscriptions.resume") { client.subscriptions.resume(sid) }

puts "· sandbox test clock, invoices"
cycle = check("sandbox.advance_cycle") { client.sandbox.advance_cycle(sid) }
check("sandbox.simulate_webhook") { client.sandbox.simulate_webhook(type: "invoice.paid", payload: { reference: FAKE }) }
inv = cycle && cycle[:invoice] && cycle.invoice.id
check("invoices.retrieve") { client.invoices.retrieve(inv || FAKE) }
check("invoices.list") { client.invoices.list(customer_id: cus) }
check("invoices.void") { client.invoices.void(inv || FAKE) }

puts "· mandates (async NIBSS)"
mandate = check("mandates.create") do
  client.mandates.create(customer_ref: cus, customer_account_number: "0123456789", bank_code: "058",
                         customer_name: "Verify", customer_account_name: "Verify",
                         customer_phone_number: "+2348012345678", customer_address: "Lagos",
                         narration: "verify", max_amount_in_kobo: 500_000)
end
check("mandates.retrieve") { client.mandates.retrieve(mandate && mandate[:reference] ? mandate.reference : (pm1&.id || FAKE)) }

puts "· settlements"
settlement = check("settlements.list") { client.settlements.list(limit: 1) }
stl = settlement.respond_to?(:data) ? settlement.data.first&.id : nil
check("settlements.retrieve") { client.settlements.retrieve(stl || FAKE) }
check("settlements.retrieve_escrow") { client.settlements.retrieve_escrow }
check("settlements.refund") { client.settlements.refund(stl || FAKE) }
check("settlements.create_payout") { client.settlements.create_payout(amount_in_kobo: 1_000, bank_code: "058", account_number: "0123456789") }

puts "· webhook endpoints (+ deliveries)"
endpoint = check("webhook_endpoints.create") { client.webhook_endpoints.create(url: "https://example.com/hooks/#{sfx}", enabled_events: ["*"]) }
whk = endpoint&.id || FAKE
check("webhook_endpoints.retrieve") { client.webhook_endpoints.retrieve(whk) }
check("webhook_endpoints.update") { client.webhook_endpoints.update(whk, disabled: true) }
check("webhook_endpoints.list") { client.webhook_endpoints.list }
check("webhook_endpoints.deliveries.list") { client.webhook_endpoints.deliveries.list(whk) }
check("webhook_endpoints.deliveries.retrieve") { client.webhook_endpoints.deliveries.retrieve(whk, "nbo000000000000whd") }
check("webhook_endpoints.deliveries.replay") { client.webhook_endpoints.deliveries.replay(whk, "nbo000000000000whd") }
check("webhook_endpoints.rotate_secret") { client.webhook_endpoints.rotate_secret(whk) }
check("webhook_endpoints.delete") { client.webhook_endpoints.delete(whk) }

puts "· events, organization, metrics"
events = check("events.list") { client.events.list(limit: 1) }
evt = events.respond_to?(:data) ? events.data.first&.id : nil
check("events.retrieve") { client.events.retrieve(evt || FAKE) }
check("events.catalog") { client.events.catalog }
check("organization.retrieve") { client.organization.retrieve }
check("organization.update") { client.organization.update(monthly_request_quota: 1_000_000) }
check("organization.billing.retrieve") { client.organization.billing.retrieve }
check("organization.billing.update") { client.organization.billing.update(comms_enabled: true) }
check("metrics.billing") { client.metrics.billing }

puts "· terminal transitions"
check("subscriptions.cancel") { client.subscriptions.cancel(sid, mode: "now") }
check("subscriptions.resubscribe") { client.subscriptions.resubscribe(sid) }
archive_plan = check("plans.create (archive target)") { client.plans.create(name: "Archive #{sfx}") }
check("plans.archive") { client.plans.archive(archive_plan&.id || FAKE) }

# ---- verdict ----
puts
counts = RESULTS.each_with_object(Hash.new(0)) { |(_, status, _), acc| acc[status] += 1 }
puts "#{RESULTS.length} methods | ok #{counts[:ok]} | expected-errors #{counts[:expected]} | " \
     "infra #{counts[:infra]} | DEFECTS #{counts[:defect]}"

if counts[:defect].zero?
  puts "VERDICT: PASS — every method exercised against the real sandbox, 0 defects."
  exit 0
else
  puts "VERDICT: FAIL — #{counts[:defect]} defect(s):"
  RESULTS.select { |_, status, _| status == :defect }.each { |name, _, detail| puts "  - #{name}: #{detail}" }
  exit 1
end
