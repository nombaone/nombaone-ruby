# frozen_string_literal: true

# Sandbox dunning rehearsal — make a thin-balance decline happen on demand with
# the test clock, then read where recovery stands. `past_due` is not canceled.
#
#   NOMBAONE_API_KEY=nbo_sandbox_… ruby -Ilib examples/05_sandbox_cycle.rb

require "nombaone"
require "securerandom"

nombaone = Nombaone.new(ENV.fetch("NOMBAONE_API_KEY"), base_url: ENV["NOMBAONE_BASE_URL"])
suffix = SecureRandom.hex(4)

plan = nombaone.plans.create(name: "Dunning #{suffix}")
price = nombaone.plans.prices.create(plan.id, unit_amount_in_kobo: 250_000, interval: "month")
customer = nombaone.customers.create(email: "dun+#{suffix}@example.com", name: "Katherine Johnson")

# A card that declines like a thin balance does — "not yet", not "no".
method = nombaone.sandbox.create_payment_method(
  customer_id: customer.id, behavior: "decline_insufficient_funds",
)

# Start with a trial so the first charge is deferred — we trigger the decline
# ourselves on the next cycle (the honest way to rehearse dunning).
sub = nombaone.subscriptions.create(
  customer_id: customer.id, price_id: price.id, payment_method_id: method.id, trial_days: 14,
)
puts "subscription: #{sub.id} status=#{sub.status}"

# The test clock: force the next billing cycle through the real engine.
cycle = nombaone.sandbox.advance_cycle(sub.id)
puts "cycle:        outcome=#{cycle.outcome} invoice=#{cycle.invoice.id} " \
     "due=₦#{cycle.invoice.amount_due_in_kobo / 100}"

# Where does recovery stand? Honor grace_access_until before cutting anyone off.
dunning = nombaone.subscriptions.dunning.retrieve(sub.id)
puts "dunning:      status=#{dunning.status} attempts=#{dunning.attempts_used}/#{dunning.max_attempts}"
puts "grace until:  #{dunning.grace_access_until || '—'}"

reloaded = nombaone.subscriptions.retrieve(sub.id)
puts "subscription: status=#{reloaded.status} (past_due is recoverable, not canceled)"
