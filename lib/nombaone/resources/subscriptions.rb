# frozen_string_literal: true

module Nombaone
  module Resources
    # Scheduled (next-cycle) changes queued against a subscription
    # (`nombaone.subscriptions.schedule`).
    class SubscriptionSchedules < BaseResource
      # Queue a change for the next cycle boundary — the safe way to switch
      # billing intervals (mid-cycle interval proration is unsupported).
      #
      # @param subscription_id [String] `nbo…sub`
      # @param price_id [String] the price to switch to at the boundary.
      # @param quantity [Integer]
      # @param effective_at [String] defaults to `"next_cycle"` server-side.
      # @param request_options [Hash]
      # @return [NombaObject]
      # @raise [Nombaone::ConflictError] 409 `SUBSCRIPTION_SCHEDULE_CONFLICT`
      def create(subscription_id, price_id:, quantity: OMIT, effective_at: OMIT,
                 request_options: {})
        request(:post, "/subscriptions/#{encode(subscription_id)}/schedule",
                body: { price_id: price_id, quantity: quantity, effective_at: effective_at },
                options: request_options)
      end

      # Retrieve the subscription's schedule.
      #
      # @param subscription_id [String] `nbo…sub`
      # @param request_options [Hash]
      # @return [NombaObject]
      # @raise [Nombaone::NotFoundError] 404 `SUBSCRIPTION_SCHEDULE_NOT_FOUND`
      def retrieve(subscription_id, request_options: {})
        request(:get, "/subscriptions/#{encode(subscription_id)}/schedule",
                options: request_options)
      end

      # Cancel the pending schedule before it applies.
      #
      # @param subscription_id [String] `nbo…sub`
      # @param request_options [Hash]
      # @return [NombaObject]
      def release(subscription_id, request_options: {})
        request(:delete, "/subscriptions/#{encode(subscription_id)}/schedule",
                options: request_options)
      end
    end

    # Read-only view into a subscription's recovery state
    # (`nombaone.subscriptions.dunning`).
    class SubscriptionDunning < BaseResource
      # Where the subscription stands in dunning. Check `grace_access_until`
      # before cutting access — `past_due` usually means "not yet", not "no".
      #
      # @param subscription_id [String] `nbo…sub`
      # @param request_options [Hash]
      # @return [NombaObject]
      def retrieve(subscription_id, request_options: {})
        request(:get, "/subscriptions/#{encode(subscription_id)}/dunning", options: request_options)
      end

      # List every recovery attempt, newest first.
      #
      # @param subscription_id [String] `nbo…sub`
      # @param limit [Integer] page size, 1–100 (API default 20).
      # @param cursor [String] opaque cursor from a previous page.
      # @param request_options [Hash]
      # @return [Page<NombaObject>]
      def list_attempts(subscription_id, limit: OMIT, cursor: OMIT, request_options: {})
        request_page("/subscriptions/#{encode(subscription_id)}/dunning/attempts",
                     query: { limit: limit, cursor: cursor }, options: request_options)
      end
    end

    # Subscriptions — the core object. Create one against a customer and a
    # price; the engine handles cycles, invoices, retries, and recovery.
    #
    # Involuntary churn is `status: "canceled"` with
    # `cancellation_reason: "involuntary"` (there is no separate `churned`
    # status; there IS a `subscription.churned` event). `past_due` is **not**
    # canceled — read {#dunning} and honor `grace_access_until`.
    #
    # @example
    #   subscription = nombaone.subscriptions.create(
    #     customer_id: customer.id, price_id: price.id, payment_method_id: method.id
    #   )
    #   subscription.status # => "active"
    class Subscriptions < BaseResource
      # Scheduled (next-cycle) changes.
      # @return [SubscriptionSchedules]
      def schedule
        @schedule ||= SubscriptionSchedules.new(@client)
      end

      # Recovery/dunning state (read-only).
      # @return [SubscriptionDunning]
      def dunning
        @dunning ||= SubscriptionDunning.new(@client)
      end

      # Create a subscription. This can move money (the first charge), so the
      # API requires an `Idempotency-Key`; the SDK sends one automatically and
      # reuses it across its own retries.
      #
      # @param customer_id [String] `nbo…cus`
      # @param price_id [String] `nbo…prc` — subscriptions reference a price, not a plan.
      # @param payment_method_id [String] required for `charge_automatically`
      #   unless `trial_days > 0` (the first charge is deferred to trial end).
      # @param collection_method [String] `"charge_automatically"` (default) or
      #   `"send_invoice"`.
      # @param trial_days [Integer]
      # @param quantity [Integer] defaults to 1 server-side.
      # @param metadata [Hash]
      # @param request_options [Hash]
      # @return [NombaObject]
      # @raise [Nombaone::ValidationError] 422 — e.g. a missing payment method without a trial.
      # @raise [Nombaone::ConflictError] 409 `SUBSCRIPTION_PAYMENT_METHOD_REQUIRED`
      def create(customer_id:, price_id:, payment_method_id: OMIT, collection_method: OMIT,
                 trial_days: OMIT, quantity: OMIT, metadata: OMIT, request_options: {})
        request(:post, "/subscriptions",
                body: {
                  customer_id: customer_id,
                  price_id: price_id,
                  payment_method_id: payment_method_id,
                  collection_method: collection_method,
                  trial_days: trial_days,
                  quantity: quantity,
                  metadata: metadata,
                },
                options: request_options)
      end

      # Retrieve a subscription by id.
      #
      # @param id [String] `nbo…sub`
      # @param request_options [Hash]
      # @return [NombaObject]
      # @raise [Nombaone::NotFoundError] 404 `SUBSCRIPTION_NOT_FOUND`
      def retrieve(id, request_options: {})
        request(:get, "/subscriptions/#{encode(id)}", options: request_options)
      end

      # Edit metadata or the default payment method. For a price, quantity, or
      # interval change (which prorates), use {#change}. At least one field is required.
      #
      # @param id [String] `nbo…sub`
      # @param default_payment_method_id [String]
      # @param metadata [Hash]
      # @param request_options [Hash]
      # @return [NombaObject]
      def update(id, default_payment_method_id: OMIT, metadata: OMIT, request_options: {})
        request(:patch, "/subscriptions/#{encode(id)}",
                body: { default_payment_method_id: default_payment_method_id, metadata: metadata },
                options: request_options)
      end

      # List subscriptions, newest first.
      #
      # @param customer_id [String] filter to one customer (`nbo…cus`).
      # @param status [String] filter by subscription status.
      # @param limit [Integer] page size, 1–100 (API default 20).
      # @param cursor [String] opaque cursor from a previous page.
      # @param request_options [Hash]
      # @return [Page<NombaObject>]
      def list(customer_id: OMIT, status: OMIT, limit: OMIT, cursor: OMIT, request_options: {})
        request_page("/subscriptions",
                     query: { customer_id: customer_id, status: status, limit: limit,
                              cursor: cursor },
                     options: request_options)
      end

      # The subscription's audit trail of domain events, newest first.
      #
      # @param id [String] `nbo…sub`
      # @param limit [Integer] page size, 1–100 (API default 20).
      # @param cursor [String] opaque cursor from a previous page.
      # @param request_options [Hash]
      # @return [Page<NombaObject>]
      def list_events(id, limit: OMIT, cursor: OMIT, request_options: {})
        request_page("/subscriptions/#{encode(id)}/events",
                     query: { limit: limit, cursor: cursor }, options: request_options)
      end

      # Pause billing. The subscription keeps its place in the cycle and resumes cleanly.
      #
      # @param id [String] `nbo…sub`
      # @param max_days [Integer] auto-resume after this many days.
      # @param request_options [Hash]
      # @return [NombaObject]
      # @raise [Nombaone::ConflictError] 409 `SUBSCRIPTION_ILLEGAL_TRANSITION`
      def pause(id, max_days: OMIT, request_options: {})
        request(:post, "/subscriptions/#{encode(id)}/pause",
                body: { max_days: max_days }, options: request_options)
      end

      # Resume a paused subscription.
      #
      # @param id [String] `nbo…sub`
      # @param request_options [Hash]
      # @return [NombaObject]
      def resume(id, request_options: {})
        request(:post, "/subscriptions/#{encode(id)}/resume", body: {}, options: request_options)
      end

      # Cancel a subscription — immediately (default) or at period end.
      #
      # @param id [String] `nbo…sub`
      # @param mode [String] `"now"` (default) or `"at_period_end"` (keeps
      #   access until the cycle closes).
      # @param comment [String]
      # @param request_options [Hash]
      # @return [NombaObject]
      #
      # @example
      #   nombaone.subscriptions.cancel(subscription.id, mode: "at_period_end")
      def cancel(id, mode: OMIT, comment: OMIT, request_options: {})
        request(:post, "/subscriptions/#{encode(id)}/cancel",
                body: { mode: mode, comment: comment }, options: request_options)
      end

      # Start a fresh subscription for a canceled one's customer, reusing the
      # old price/payment method unless overridden. The subscription must be in
      # a terminal state.
      #
      # @param id [String] `nbo…sub`
      # @param price_id [String] defaults to the previous price.
      # @param payment_method_id [String] defaults to the previous payment method.
      # @param request_options [Hash]
      # @return [NombaObject]
      # @raise [Nombaone::ConflictError] 409 `SUBSCRIPTION_NOT_TERMINAL`
      def resubscribe(id, price_id: OMIT, payment_method_id: OMIT, request_options: {})
        request(:post, "/subscriptions/#{encode(id)}/resubscribe",
                body: { price_id: price_id, payment_method_id: payment_method_id },
                options: request_options)
      end

      # Change price or quantity mid-cycle, prorating by default. Switching the
      # billing interval mid-cycle is unsupported
      # (`PRORATION_INTERVAL_SWITCH_UNSUPPORTED`) — queue it with {#schedule} instead.
      #
      # @param id [String] `nbo…sub`
      # @param price_id [String]
      # @param quantity [Integer]
      # @param interval_switch [Boolean]
      # @param proration_behavior [String] `"create_prorations"` (default) or `"none"`.
      # @param request_options [Hash]
      # @return [NombaObject]
      #
      # @example
      #   nombaone.subscriptions.change(subscription.id, price_id: bigger_price.id)
      def change(id, price_id: OMIT, quantity: OMIT, interval_switch: OMIT,
                 proration_behavior: OMIT, request_options: {})
        request(:post, "/subscriptions/#{encode(id)}/change",
                body: {
                  price_id: price_id,
                  quantity: quantity,
                  interval_switch: interval_switch,
                  proration_behavior: proration_behavior,
                },
                options: request_options)
      end

      # Swap the payment method that bills this subscription — the card-update
      # path during dunning. Provide exactly one of `payment_method_reference`
      # or `checkout_token`.
      #
      # @param id [String] `nbo…sub`
      # @param payment_method_reference [String] an already-captured method (`nbo…pmt`).
      # @param checkout_token [String] a fresh hosted-checkout token — attaches and swaps atomically.
      # @param request_options [Hash]
      # @return [NombaObject]
      def update_payment_method(id, payment_method_reference: OMIT, checkout_token: OMIT,
                                request_options: {})
        request(:post, "/subscriptions/#{encode(id)}/payment-method",
                body: {
                  payment_method_reference: payment_method_reference,
                  checkout_token: checkout_token,
                },
                options: request_options)
      end

      # Preview the next invoice without charging or storing anything.
      #
      # @param id [String] `nbo…sub`
      # @param request_options [Hash]
      # @return [NombaObject]
      def retrieve_upcoming_invoice(id, request_options: {})
        request(:get, "/subscriptions/#{encode(id)}/upcoming-invoice", options: request_options)
      end

      # Apply a coupon to this subscription only.
      #
      # @param id [String] `nbo…sub`
      # @param coupon [String] a coupon id (`nbo…cpn`) or its code.
      # @param request_options [Hash]
      # @return [NombaObject]
      def apply_discount(id, coupon:, request_options: {})
        request(:post, "/subscriptions/#{encode(id)}/discount",
                body: { coupon: coupon }, options: request_options)
      end

      # Remove the subscription's active discount. Returns the ended discount.
      #
      # @param id [String] `nbo…sub`
      # @param request_options [Hash]
      # @return [NombaObject]
      def remove_discount(id, request_options: {})
        request(:delete, "/subscriptions/#{encode(id)}/discount", options: request_options)
      end
    end
  end
end
