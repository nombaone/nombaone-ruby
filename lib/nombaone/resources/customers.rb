# frozen_string_literal: true

module Nombaone
  module Resources
    # Customers — the people and businesses you bill.
    #
    # @example
    #   customer = nombaone.customers.create(email: "ada@example.com", name: "Ada Lovelace")
    #   customer.id # => "nbo…cus"
    class Customers < BaseResource
      # Create a customer.
      #
      # @param email [String] unique per organization + environment
      #   (`CUSTOMER_EMAIL_TAKEN` on reuse).
      # @param name [String]
      # @param phone [String, nil]
      # @param metadata [Hash] free-form annotations (keys are stored verbatim).
      # @param request_options [Hash] per-call overrides (`:idempotency_key`,
      #   `:headers`, `:timeout`, `:max_retries`, `:cancel_when`).
      # @return [NombaObject] the created customer.
      # @raise [Nombaone::ValidationError] 422 `CLIENT_VALIDATION_FAILED` — see `error.fields`.
      # @raise [Nombaone::ConflictError] 409 `CUSTOMER_EMAIL_TAKEN` — reuse the existing customer.
      #
      # @example
      #   customer = nombaone.customers.create(
      #     email: "ada@example.com",
      #     name: "Ada Lovelace",
      #     metadata: { crm_id: "crm_812" },
      #   )
      def create(email:, name:, phone: OMIT, metadata: OMIT, request_options: {})
        request(:post, "/customers",
                body: { email: email, name: name, phone: phone, metadata: metadata },
                options: request_options)
      end

      # Retrieve a customer by id.
      #
      # @param id [String] `nbo…cus`
      # @param request_options [Hash]
      # @return [NombaObject]
      # @raise [Nombaone::NotFoundError] 404 `CUSTOMER_NOT_FOUND` — check the id
      #   and that your key matches the environment the customer was created in.
      def retrieve(id, request_options: {})
        request(:get, "/customers/#{encode(id)}", options: request_options)
      end

      # Update a customer's mutable fields. At least one field is required.
      #
      # @param id [String] `nbo…cus`
      # @param name [String]
      # @param phone [String, nil] pass `nil` to clear the phone number.
      # @param metadata [Hash]
      # @param request_options [Hash]
      # @return [NombaObject]
      #
      # @example
      #   nombaone.customers.update(customer.id, phone: "+2348012345678")
      def update(id, name: OMIT, phone: OMIT, metadata: OMIT, request_options: {})
        request(:patch, "/customers/#{encode(id)}",
                body: { name: name, phone: phone, metadata: metadata },
                options: request_options)
      end

      # List customers, newest first.
      #
      # @param email [String] exact-match filter on email.
      # @param limit [Integer] page size, 1–100 (API default 20).
      # @param cursor [String] opaque cursor from a previous page's `next_cursor`.
      # @param request_options [Hash]
      # @return [Page<NombaObject>]
      #
      # @example
      #   nombaone.customers.list.each { |customer| puts customer.email }
      def list(email: OMIT, limit: OMIT, cursor: OMIT, request_options: {})
        request_page("/customers",
                     query: { email: email, limit: limit, cursor: cursor },
                     options: request_options)
      end

      # Apply a coupon to a customer. The resulting discount shapes every future
      # invoice for the customer until it ends or is removed.
      #
      # @param id [String] `nbo…cus`
      # @param coupon [String] a coupon id (`nbo…cpn`) or its code (e.g. `"LAUNCH20"`).
      # @param request_options [Hash]
      # @return [NombaObject] the created discount.
      # @raise [Nombaone::NotFoundError] 404 `COUPON_NOT_FOUND`
      # @raise [Nombaone::ConflictError] 409 `COUPON_ALREADY_APPLIED`
      #
      # @example
      #   nombaone.customers.apply_discount(customer.id, coupon: "LAUNCH20")
      def apply_discount(id, coupon:, request_options: {})
        request(:post, "/customers/#{encode(id)}/discount",
                body: { coupon: coupon }, options: request_options)
      end

      # Remove the customer's active discount. Returns the ended discount.
      #
      # @param id [String] `nbo…cus`
      # @param request_options [Hash]
      # @return [NombaObject]
      def remove_discount(id, request_options: {})
        request(:delete, "/customers/#{encode(id)}/discount", options: request_options)
      end

      # Grant credit to a customer. Credit is drawn down oldest-grant-first by
      # future invoices **before** any payment rail is charged.
      #
      # This moves money-shaped state, so the API requires an `Idempotency-Key`;
      # the SDK sends one automatically. Pass `request_options[:idempotency_key]`
      # to keep the grant idempotent across process restarts.
      #
      # @param id [String] `nbo…cus`
      # @param amount_in_kobo [Integer] amount to grant, **integer kobo**
      #   (₦1.00 = 100). `250_000` is ₦2,500 — not ₦250,000. Multiply naira by
      #   100 exactly once, at the edge of your system.
      # @param source [String] `"manual"` or `"goodwill"` (defaults to `manual`).
      # @param source_reference [String] your own reference (ticket, promo id, …).
      # @param metadata [Hash]
      # @param request_options [Hash]
      # @return [NombaObject] the created credit grant.
      #
      # @example
      #   nombaone.customers.grant_credit(customer.id, amount_in_kobo: 250_000, source: "goodwill")
      def grant_credit(id, amount_in_kobo:, source: OMIT, source_reference: OMIT,
                       metadata: OMIT, request_options: {})
        request(:post, "/customers/#{encode(id)}/credit",
                body: {
                  amount_in_kobo: amount_in_kobo,
                  source: source,
                  source_reference: source_reference,
                  metadata: metadata,
                },
                options: request_options)
      end

      # Retrieve the customer's credit balance and the grants behind it.
      #
      # @param id [String] `nbo…cus`
      # @param request_options [Hash]
      # @return [NombaObject] with `balance_in_kobo` and `grants`.
      def retrieve_credit_balance(id, request_options: {})
        request(:get, "/customers/#{encode(id)}/credit", options: request_options)
      end

      # Void a credit grant — its remaining balance becomes unusable. Consumed
      # credit is untouched.
      #
      # @param id [String] `nbo…cus`
      # @param grant_id [String] `nbo…crg`
      # @param request_options [Hash]
      # @return [NombaObject]
      # @raise [Nombaone::ConflictError] 409 `CREDIT_GRANT_ALREADY_VOIDED`
      def void_credit(id, grant_id, request_options: {})
        request(:delete, "/customers/#{encode(id)}/credit/#{encode(grant_id)}",
                options: request_options)
      end
    end
  end
end
