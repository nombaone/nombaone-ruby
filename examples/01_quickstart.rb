# frozen_string_literal: true

# Quickstart — you are three objects away from a live subscription.
#
#   NOMBAONE_API_KEY=nbo_sandbox_… ruby -Ilib examples/01_quickstart.rb
#
# The client derives the host from your key prefix; override with NOMBAONE_BASE_URL.

require "nombaone"
require "securerandom"

nombaone = Nombaone.new(ENV.fetch("NOMBAONE_API_KEY"), base_url: ENV["NOMBAONE_BASE_URL"])
suffix = SecureRandom.hex(4)

plan = nombaone.plans.create(name: "Pro #{suffix}")
price = nombaone.plans.prices.create(plan.id, unit_amount_in_kobo: 250_000, interval: "month")
customer = nombaone.customers.create(email: "ada+#{suffix}@example.com", name: "Ada Lovelace")

# Sandbox: mint a deterministic test card, then subscribe.
method = nombaone.sandbox.create_payment_method(customer_id: customer.id, behavior: "success")
subscription = nombaone.subscriptions.create(
  customer_id: customer.id,
  price_id: price.id,
  payment_method_id: method.id,
)

puts "plan:         #{plan.id} (#{plan.name})"
puts "price:        #{price.id} — ₦#{price.unit_amount_in_kobo / 100} / #{price.interval}"
puts "customer:     #{customer.id} (#{customer.email})"
puts "method:       #{method.id} (#{method.kind})"
puts "subscription: #{subscription.id} — status=#{subscription.status}"
