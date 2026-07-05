# frozen_string_literal: true

# The subscription lifecycle — create, upgrade (prorated), pause, resume, cancel.
#
#   NOMBAONE_API_KEY=nbo_sandbox_… ruby -Ilib examples/03_subscription_lifecycle.rb

require "nombaone"
require "securerandom"

nombaone = Nombaone.new(ENV.fetch("NOMBAONE_API_KEY"), base_url: ENV["NOMBAONE_BASE_URL"])
suffix = SecureRandom.hex(4)

plan = nombaone.plans.create(name: "Lifecycle #{suffix}")
starter = nombaone.plans.prices.create(plan.id, unit_amount_in_kobo: 250_000, interval: "month")
pro = nombaone.plans.prices.create(plan.id, unit_amount_in_kobo: 500_000, interval: "month")
customer = nombaone.customers.create(email: "life+#{suffix}@example.com", name: "Grace Hopper")
method = nombaone.sandbox.create_payment_method(customer_id: customer.id, behavior: "success")

sub = nombaone.subscriptions.create(
  customer_id: customer.id, price_id: starter.id, payment_method_id: method.id,
)
puts "created:  #{sub.id} status=#{sub.status} price=#{sub.price_id}"

# Upgrade mid-cycle — prorated on the next invoice by default.
sub = nombaone.subscriptions.change(sub.id, price_id: pro.id)
puts "upgraded: price=#{sub.price_id}"

# Pause and resume — keeps its place in the cycle.
sub = nombaone.subscriptions.pause(sub.id)
puts "paused:   status=#{sub.status}"
sub = nombaone.subscriptions.resume(sub.id)
puts "resumed:  status=#{sub.status}"

# Cancel at period end — the subscriber keeps access until the cycle closes.
sub = nombaone.subscriptions.cancel(sub.id, mode: "at_period_end")
puts "canceled: status=#{sub.status} cancel_at_period_end=#{sub.cancel_at_period_end}"
