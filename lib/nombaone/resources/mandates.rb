# frozen_string_literal: true

module Nombaone
  module Resources
    # Direct-debit mandates (NIBSS). Creation is **asynchronous**: the mandate
    # starts `consent_pending` and activates only after the customer authorizes
    # it with their bank — the engine sweeps for activation and fires
    # `payment_method.attached` / `payment_method.updated`. Don't poll in a tight
    # loop; listen for the webhook, and don't charge before it's active
    # (`MANDATE_NOT_ACTIVE` / `MANDATE_CONSENT_PENDING`).
    class Mandates < BaseResource
      # Create a mandate. Requires an `Idempotency-Key` (sent automatically).
      #
      # @param customer_ref [String] the customer this mandate belongs to (`nbo…cus`).
      # @param customer_account_number [String]
      # @param bank_code [String] CBN 3-digit bank code (058 GTB · 044 Access · 033 UBA · …).
      # @param customer_name [String]
      # @param customer_account_name [String]
      # @param customer_phone_number [String]
      # @param customer_address [String]
      # @param narration [String] shown on the customer's statement.
      # @param max_amount_in_kobo [Integer] hard per-debit ceiling, **integer
      #   kobo** (₦1.00 = 100). Charges above it fail with `MANDATE_MAX_AMOUNT_EXCEEDED`.
      # @param frequency [String] defaults to `"monthly"` server-side.
      # @param start_date [String] local date-time (no zone); defaults to tomorrow.
      # @param end_date [String] local date-time (no zone); defaults to one year out.
      # @param request_options [Hash]
      # @return [NombaObject] the pending mandate setup; relay its
      #   `consent_instruction` to the customer, then wait for the webhook.
      #
      # @example
      #   mandate = nombaone.mandates.create(
      #     customer_ref: customer.id, customer_account_number: "0123456789", bank_code: "058",
      #     customer_name: "Ada Lovelace", customer_account_name: "Ada Lovelace",
      #     customer_phone_number: "+2348012345678", customer_address: "1 Marina, Lagos",
      #     narration: "Acme Pro subscription", max_amount_in_kobo: 500_000
      #   )
      def create(customer_ref:, customer_account_number:, bank_code:, customer_name:,
                 customer_account_name:, customer_phone_number:, customer_address:, narration:,
                 max_amount_in_kobo:, frequency: OMIT, start_date: OMIT, end_date: OMIT,
                 request_options: {})
        request(:post, "/mandates",
                body: {
                  customer_ref: customer_ref,
                  customer_account_number: customer_account_number,
                  bank_code: bank_code,
                  customer_name: customer_name,
                  customer_account_name: customer_account_name,
                  customer_phone_number: customer_phone_number,
                  customer_address: customer_address,
                  narration: narration,
                  max_amount_in_kobo: max_amount_in_kobo,
                  frequency: frequency,
                  start_date: start_date,
                  end_date: end_date,
                },
                options: request_options)
      end

      # Check a mandate's current standing. Returns the underlying
      # **payment-method** row (its `status` moves `consent_pending` → `active`).
      #
      # @param id [String] `nbo…pmt`
      # @param request_options [Hash]
      # @return [NombaObject] a payment method.
      def retrieve(id, request_options: {})
        request(:get, "/mandates/#{encode(id)}", options: request_options)
      end
    end
  end
end
