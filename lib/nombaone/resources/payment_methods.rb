# frozen_string_literal: true

module Nombaone
  module Resources
    # Payment methods — cards (via hosted checkout), direct-debit mandates (see
    # `nombaone.mandates`), and virtual accounts for the transfer rail.
    #
    # Card and mandate are **pull** rails (the engine initiates the debit); a
    # virtual account is the **push** rail (the customer sends a transfer and
    # the engine matches it — never treat a collect as instantly final).
    class PaymentMethods < BaseResource
      # Start a hosted-checkout card capture. Card entry happens on the PCI
      # hosted page — no card data ever touches your servers. The method appears
      # as `setup_pending` until the customer completes checkout.
      #
      # @param customer_ref [String] the customer this card will belong to (`nbo…cus`).
      # @param amount_in_kobo [Integer] the validation charge, **integer kobo** (₦1.00 = 100).
      # @param callback_url [String] where the hosted checkout returns the customer.
      # @param request_options [Hash]
      # @return [NombaObject] with a `checkout_link` to redirect the customer to.
      #
      # @example
      #   setup = nombaone.payment_methods.setup(
      #     customer_ref: customer.id, amount_in_kobo: 5_000, callback_url: "https://example.com/return"
      #   )
      #   # redirect the customer to setup.checkout_link
      def setup(customer_ref:, amount_in_kobo:, callback_url:, request_options: {})
        request(:post, "/payment-methods/setup",
                body: {
                  customer_ref: customer_ref,
                  amount_in_kobo: amount_in_kobo,
                  callback_url: callback_url,
                },
                options: request_options)
      end

      # Issue a dedicated virtual account (NUBAN) so the customer can pay by
      # bank transfer. The engine matches inbound transfers to invoices by
      # reference and exact integer-kobo amount.
      #
      # @param customer_ref [String] the customer to issue the account for (`nbo…cus`).
      # @param expected_amount [Integer] optional expected amount hint, integer kobo.
      # @param expiry_date [String] optional ISO date the account should expire.
      # @param request_options [Hash]
      # @return [NombaObject]
      def create_virtual_account(customer_ref:, expected_amount: OMIT, expiry_date: OMIT,
                                 request_options: {})
        request(:post, "/payment-methods/virtual-account",
                body: {
                  customer_ref: customer_ref,
                  expected_amount: expected_amount,
                  expiry_date: expiry_date,
                },
                options: request_options)
      end

      # Retrieve a payment method by id.
      #
      # @param id [String] `nbo…pmt`
      # @param request_options [Hash]
      # @return [NombaObject]
      # @raise [Nombaone::NotFoundError] 404 `PAYMENT_METHOD_NOT_FOUND`
      def retrieve(id, request_options: {})
        request(:get, "/payment-methods/#{encode(id)}", options: request_options)
      end

      # List payment methods, newest first.
      #
      # @param customer_ref [String] filter to one customer (`nbo…cus`). Note
      #   the wire filter name is `customerRef`.
      # @param limit [Integer] page size, 1–100 (API default 20).
      # @param cursor [String] opaque cursor from a previous page.
      # @param request_options [Hash]
      # @return [Page<NombaObject>]
      def list(customer_ref: OMIT, limit: OMIT, cursor: OMIT, request_options: {})
        request_page("/payment-methods",
                     query: { customer_ref: customer_ref, limit: limit, cursor: cursor },
                     options: request_options)
      end

      # Make this the customer's default payment method.
      #
      # @param id [String] `nbo…pmt`
      # @param request_options [Hash]
      # @return [NombaObject]
      def set_default(id, request_options: {})
        request(:post, "/payment-methods/#{encode(id)}/default", body: {}, options: request_options)
      end

      # Detach a payment method. Subscriptions still billing against it will
      # need a replacement (`SUBSCRIPTION_PAYMENT_METHOD_REQUIRED` at next charge
      # otherwise).
      #
      # @param id [String] `nbo…pmt`
      # @param request_options [Hash]
      # @return [NombaObject]
      def remove(id, request_options: {})
        request(:delete, "/payment-methods/#{encode(id)}", options: request_options)
      end
    end
  end
end
