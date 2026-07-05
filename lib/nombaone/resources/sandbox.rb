# frozen_string_literal: true

module Nombaone
  module Resources
    # **Sandbox only.** Simulation instruments that make billing outcomes happen
    # on demand — no cron waits, no real cards. These endpoints exist only on
    # the sandbox deployment; calling any of them with a live key raises
    # locally, **before any network request**.
    class Sandbox < BaseResource
      # **Sandbox only.** Mint a ready, chargeable test payment method whose
      # `behavior` decides every future charge outcome deterministically.
      #
      # @param customer_id [String] `nbo…cus`
      # @param behavior [String] `"success"` (default), `"decline_insufficient_funds"`,
      #   `"decline_expired_card"`, `"decline_do_not_honor"`, or `"requires_otp"`.
      # @param kind [String] `"card"` (default) or `"mandate"`.
      # @param request_options [Hash]
      # @return [NombaObject] a payment method.
      #
      # @example
      #   method = nombaone.sandbox.create_payment_method(
      #     customer_id: customer.id, behavior: "decline_insufficient_funds"
      #   )
      def create_payment_method(customer_id:, behavior: OMIT, kind: OMIT, request_options: {})
        assert_sandbox!
        request(:post, "/sandbox/payment-methods",
                body: { customer_id: customer_id, behavior: behavior, kind: kind },
                options: request_options)
      end

      # **Sandbox only.** The test clock: run the subscription's next billing
      # cycle right now, through the real engine — invoice, charge, ledger,
      # webhooks and all.
      #
      # @param subscription_id [String] `nbo…sub`
      # @param request_options [Hash]
      # @return [NombaObject] the cycle `outcome` and the `invoice` it produced.
      #
      # @example
      #   result = nombaone.sandbox.advance_cycle(subscription.id)
      #   result.outcome # => "paid"
      def advance_cycle(subscription_id, request_options: {})
        assert_sandbox!
        request(:post, "/sandbox/subscriptions/#{encode(subscription_id)}/advance-cycle",
                body: {}, options: request_options)
      end

      # **Sandbox only.** Emit a real, signed catalog event to your registered
      # endpoints — the genuine pipeline (real secret, real signature, real
      # retries), not a mock. This is how you rehearse your handler.
      #
      # @param type [String] any catalog event type, e.g. `"invoice.payment_failed"`.
      # @param payload [Hash] shapes the delivery's `data` object.
      # @param request_options [Hash]
      # @return [NombaObject]
      #
      # @example
      #   nombaone.sandbox.simulate_webhook(
      #     type: "invoice.payment_failed",
      #     payload: { reference: invoice.id, reason: "insufficient_funds" }
      #   )
      def simulate_webhook(type:, payload: OMIT, request_options: {})
        assert_sandbox!
        request(:post, "/sandbox/webhooks/simulate",
                body: { type: type, payload: payload }, options: request_options)
      end

      private

      # Fail locally, before any network call, when constructed with a live key.
      def assert_sandbox!
        return unless @client.mode == "live"

        raise Error,
              "nombaone.sandbox.* only works with a sandbox key (nbo_sandbox_…) — the " \
              "/v1/sandbox endpoints do not exist on the live API. Use your sandbox key to " \
              "rehearse, then go live without the sandbox calls."
      end
    end
  end
end
