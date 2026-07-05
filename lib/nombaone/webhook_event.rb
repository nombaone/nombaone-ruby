# frozen_string_literal: true

module Nombaone
  # Every event type the platform can deliver, as `name = value` constants
  # (`Nombaone::WebhookEventType::INVOICE_PAID == "invoice.paid"`), plus the
  # frozen {ALL} list. Branch on {WebhookEvent#type} against these.
  #
  # The catalog is **shipped open**: an event type the API adds tomorrow is
  # still delivered and parsed — it just will not have a named constant here
  # yet, and never breaks your handler.
  module WebhookEventType
    # The public event catalog (scaffold `example.*` events are excluded).
    ALL = %w[
      customer.created
      customer.updated
      coupon.created
      discount.created
      discount.removed
      plan.created
      plan.updated
      plan.archived
      price.created
      price.deactivated
      subscription.created
      subscription.updated
      subscription.trial_will_end
      subscription.activated
      subscription.paused
      subscription.resumed
      subscription.canceled
      subscription.churned
      invoice.created
      invoice.finalized
      invoice.paid
      invoice.payment_failed
      invoice.payment_partially_collected
      invoice.payment_recovered
      invoice.action_required
      invoice.voided
      payment_method.attached
      payment_method.updated
      payment_method.expiring
      settlement.created
      settlement.refunded
      settlement.payout_created
    ].freeze

    ALL.each { |type| const_set(type.upcase.tr(".", "_"), type) }
  end

  # A verified webhook delivery. It is a {NombaObject}, so every field reads
  # idiomatically:
  #
  #   event.type              # => "invoice.payment_failed"
  #   event.event.id          # => "nbo…evt"  — DEDUPE on this
  #   event.data.reason       # => "insufficient_funds"  (typed payloads narrow with the type)
  #
  # Delivery is **at-least-once** — after verification, dedupe on `event.event.id`
  # before acting. The `event` block is always present: if a delivery arrives in
  # the older flat shape (top-level `id`/`type`/`created_at`), it is synthesized
  # so dedupe still works.
  class WebhookEvent < NombaObject
  end
end
