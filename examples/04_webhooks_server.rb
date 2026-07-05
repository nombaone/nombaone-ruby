# frozen_string_literal: true

# Webhooks — verify before you parse, and dedupe on the event id (delivery is
# at-least-once, never exactly-once). Verification needs only the signing
# secret, never an API key.
#
#   ruby -Ilib examples/04_webhooks_server.rb
#
# This script simulates a delivery locally (with generate_test_header) so it
# runs with no network, then feeds it through the exact handler logic you'd run
# in production. Framework wiring is shown at the bottom.

require "nombaone"
require "json"

secret = "nbo_whsec_example_0123456789abcdef0123456789abcdef"

# In production this JSON arrives as the raw HTTP request body. Never
# re-serialize it before verifying — the exact bytes are what was signed.
raw_body = JSON.generate(
  id: "nbo000000000001whd",
  type: "invoice.payment_failed",
  event: {
    id: "nbo000000000001evt",
    type: "invoice.payment_failed",
    createdAt: "2026-07-05T10:00:00.000Z",
  },
  data: { reference: "nbo000000000001inv", reason: "insufficient_funds" },
)
signature_header = Nombaone.webhooks.generate_test_header(payload: raw_body, secret: secret)

# ---- The handler your endpoint runs on every delivery --------------------
seen = {}

handle = lambda do |body, header|
  event = Nombaone.webhooks.construct_event(body, header, secret)

  if seen[event.event.id] # at-least-once ⇒ dedupe on event.event.id
    puts "duplicate #{event.event.id} — already processed, ignoring"
    return
  end
  seen[event.event.id] = true

  case event.type
  when Nombaone::WebhookEventType::INVOICE_PAID
    puts "invoice.paid → unlock access for #{event.data.reference}"
  when Nombaone::WebhookEventType::INVOICE_PAYMENT_FAILED
    puts "invoice.payment_failed → #{event.data.reference}: #{event.data.reason}"
  when Nombaone::WebhookEventType::INVOICE_ACTION_REQUIRED
    puts "invoice.action_required → send #{event.data.checkout_link}"
  else
    puts "unhandled event type: #{event.type}"
  end
rescue Nombaone::WebhookVerificationError => e
  puts "rejected delivery: #{e.message}"
end

handle.call(raw_body, signature_header)          # verified + dispatched
handle.call(raw_body, signature_header)          # same event id → deduped
handle.call(raw_body, "t=#{Time.now.to_i},v1=deadbeef") # wrong signature → rejected

# ---- Wiring it into a framework ------------------------------------------
#
# Rails (respond 2xx fast; do heavy work async):
#
#   def receive
#     event = Nombaone.webhooks.construct_event(
#       request.raw_post,
#       request.headers["X-Nombaone-Signature"],
#       ENV.fetch("NOMBAONE_WEBHOOK_SECRET"),
#     )
#     ProcessWebhookJob.perform_later(event.event.id, event.to_h)
#     head :ok
#   rescue Nombaone::WebhookVerificationError
#     head :bad_request
#   end
#
# Sinatra / Rack:
#
#   post "/nombaone/webhooks" do
#     event = Nombaone.webhooks.construct_event(
#       request.body.read, request.env["HTTP_X_NOMBAONE_SIGNATURE"], ENV.fetch("NOMBAONE_WEBHOOK_SECRET")
#     )
#     status 200
#   end
