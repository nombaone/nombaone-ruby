# frozen_string_literal: true

module Nombaone
  module Resources
    # Invoices — read what the billing engine produced; void what should never
    # be collected. You never create invoices — subscription cycles do; amounts
    # are locked at finalization. All amounts are integer kobo.
    class Invoices < BaseResource
      # Retrieve an invoice by id.
      #
      # @param id [String] `nbo…inv`
      # @param request_options [Hash]
      # @return [NombaObject]
      # @raise [Nombaone::NotFoundError] 404 `INVOICE_NOT_FOUND`
      def retrieve(id, request_options: {})
        request(:get, "/invoices/#{encode(id)}", options: request_options)
      end

      # List invoices, newest first.
      #
      # @param customer_id [String] filter to one customer (`nbo…cus`).
      # @param subscription_id [String] filter to one subscription (`nbo…sub`).
      # @param status [String] the list filter accepts `"draft"`, `"open"`,
      #   `"paid"`, `"void"`, `"uncollectible"` (note: no `"partially_paid"`,
      #   though invoice objects can carry that status).
      # @param limit [Integer] page size, 1–100 (API default 20).
      # @param cursor [String] opaque cursor from a previous page.
      # @param request_options [Hash]
      # @return [Page<NombaObject>]
      #
      # @example
      #   nombaone.invoices.list(status: "open").each { |inv| puts inv.amount_due_in_kobo }
      def list(customer_id: OMIT, subscription_id: OMIT, status: OMIT, limit: OMIT, cursor: OMIT,
               request_options: {})
        request_page("/invoices",
                     query: {
                       customer_id: customer_id,
                       subscription_id: subscription_id,
                       status: status,
                       limit: limit,
                       cursor: cursor,
                     },
                     options: request_options)
      end

      # Void an open, unpaid invoice. Paid invoices can't be voided — refund the
      # settlement instead.
      #
      # @param id [String] `nbo…inv`
      # @param comment [String]
      # @param request_options [Hash]
      # @return [NombaObject]
      # @raise [Nombaone::ConflictError] 409 `INVOICE_NOT_VOIDABLE`
      # @raise [Nombaone::ConflictError] 409 `INVOICE_ALREADY_PAID`
      def void(id, comment: OMIT, request_options: {})
        request(:post, "/invoices/#{encode(id)}/void",
                body: { comment: comment }, options: request_options)
      end
    end
  end
end
