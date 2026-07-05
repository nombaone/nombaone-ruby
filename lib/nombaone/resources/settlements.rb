# frozen_string_literal: true

module Nombaone
  module Resources
    # Settlements — where collected money lands, and how it leaves (refunds,
    # payouts) under the escrow lock. Collections split into a non-refundable
    # platform fee plus the net to your tenant sub-account.
    class Settlements < BaseResource
      # Retrieve a settlement by id.
      #
      # @param id [String] `nbo…stl`
      # @param request_options [Hash]
      # @return [NombaObject]
      # @raise [Nombaone::NotFoundError] 404 `SETTLEMENT_NOT_FOUND`
      def retrieve(id, request_options: {})
        request(:get, "/settlements/#{encode(id)}", options: request_options)
      end

      # List settlements, newest first.
      #
      # @param status [String] filter by settlement status.
      # @param limit [Integer] page size, 1–100 (API default 20).
      # @param cursor [String] opaque cursor from a previous page.
      # @param request_options [Hash]
      # @return [Page<NombaObject>]
      def list(status: OMIT, limit: OMIT, cursor: OMIT, request_options: {})
        request_page("/settlements",
                     query: { status: status, limit: limit, cursor: cursor },
                     options: request_options)
      end

      # Your escrow lock and available-to-withdraw balance.
      #
      # @param request_options [Hash]
      # @return [NombaObject]
      def retrieve_escrow(request_options: {})
        request(:get, "/settlements/escrow", options: request_options)
      end

      # Refund a settlement's tenant share. The platform fee is never refunded.
      #
      # **Money moves here.** The API requires an `Idempotency-Key`; the SDK
      # sends one automatically, but pass your own stable
      # `request_options[:idempotency_key]` so a retry from a *new process*
      # cannot refund twice.
      #
      # @param id [String] `nbo…stl`
      # @param amount_in_kobo [Integer] **integer kobo**; defaults server-side to
      #   the full remaining refundable amount.
      # @param request_options [Hash]
      # @return [NombaObject]
      # @raise [Nombaone::ConflictError] 409 `REFUND_ALREADY_REFUNDED`
      # @raise [Nombaone::ValidationError] 422 `REFUND_AMOUNT_EXCEEDS_NET`
      def refund(id, amount_in_kobo: OMIT, request_options: {})
        request(:post, "/settlements/#{encode(id)}/refund",
                body: { amount_in_kobo: amount_in_kobo }, options: request_options)
      end

      # Withdraw settled funds to your bank account.
      #
      # **Money moves here, and the `Idempotency-Key` doubles as the payout's
      # durable `merchantTxRef`.** Always pass an explicit, stable
      # `request_options[:idempotency_key]` (e.g. your own payout id) — an
      # auto-generated key protects SDK-level retries, but a brand-new process
      # retrying with a fresh key would create a **second** payout.
      #
      # @param amount_in_kobo [Integer] **integer kobo** (₦1.00 = 100).
      # @param bank_code [String] CBN 3-digit bank code.
      # @param account_number [String]
      # @param request_options [Hash]
      # @return [NombaObject]
      # @raise [Nombaone::ConflictError] 409 `ESCROW_LOCKED`
      # @raise [Nombaone::ValidationError] 422 `PAYOUT_EXCEEDS_AVAILABLE`
      #
      # @example
      #   payout = nombaone.settlements.create_payout(
      #     amount_in_kobo: 5_000_000, bank_code: "058", account_number: "0123456789",
      #     request_options: { idempotency_key: "payout-#{my_payout_row.id}" }
      #   )
      def create_payout(amount_in_kobo:, bank_code:, account_number:, request_options: {})
        request(:post, "/settlements/payout",
                body: {
                  amount_in_kobo: amount_in_kobo,
                  bank_code: bank_code,
                  account_number: account_number,
                },
                options: request_options)
      end
    end
  end
end
