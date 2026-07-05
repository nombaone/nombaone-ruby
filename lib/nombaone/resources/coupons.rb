# frozen_string_literal: true

module Nombaone
  module Resources
    # Coupons — reusable discount rules you apply via
    # `customers.apply_discount` / `subscriptions.apply_discount`. The coupon is
    # the rule; applying it creates a discount (one application of it).
    #
    # @example
    #   coupon = nombaone.coupons.create(
    #     code: "LAUNCH20", percent_off: 20, duration: "repeating", duration_in_cycles: 3
    #   )
    class Coupons < BaseResource
      # Create a coupon. Set **exactly one** of `amount_off_in_kobo` / `percent_off`.
      #
      # @param code [String] the tenant-facing redemption code, e.g. `"LAUNCH20"`.
      # @param duration [String] `"once"`, `"repeating"`, or `"forever"`.
      # @param amount_off_in_kobo [Integer] fixed discount, **integer kobo** (₦1.00 = 100).
      # @param percent_off [Integer] percentage discount, 1–100.
      # @param duration_in_cycles [Integer] required when `duration` is `"repeating"`.
      # @param redeem_by [String] ISO-8601 date-time after which it can't be applied.
      # @param max_redemptions [Integer]
      # @param metadata [Hash]
      # @param request_options [Hash]
      # @return [NombaObject]
      # @raise [Nombaone::ValidationError] 422 `COUPON_INVALID_DEFINITION` — set
      #   exactly one of `amount_off_in_kobo` / `percent_off`.
      def create(code:, duration:, amount_off_in_kobo: OMIT, percent_off: OMIT,
                 duration_in_cycles: OMIT, redeem_by: OMIT, max_redemptions: OMIT,
                 metadata: OMIT, request_options: {})
        request(:post, "/coupons",
                body: {
                  code: code,
                  duration: duration,
                  amount_off_in_kobo: amount_off_in_kobo,
                  percent_off: percent_off,
                  duration_in_cycles: duration_in_cycles,
                  redeem_by: redeem_by,
                  max_redemptions: max_redemptions,
                  metadata: metadata,
                },
                options: request_options)
      end

      # Retrieve a coupon by id.
      #
      # @param id [String] `nbo…cpn`
      # @param request_options [Hash]
      # @return [NombaObject]
      # @raise [Nombaone::NotFoundError] 404 `COUPON_NOT_FOUND`
      def retrieve(id, request_options: {})
        request(:get, "/coupons/#{encode(id)}", options: request_options)
      end

      # Update a coupon's redeem-by, max redemptions, or metadata.
      #
      # @param id [String] `nbo…cpn`
      # @param redeem_by [String]
      # @param max_redemptions [Integer]
      # @param metadata [Hash]
      # @param request_options [Hash]
      # @return [NombaObject]
      def update(id, redeem_by: OMIT, max_redemptions: OMIT, metadata: OMIT, request_options: {})
        request(:patch, "/coupons/#{encode(id)}",
                body: {
                  redeem_by: redeem_by,
                  max_redemptions: max_redemptions,
                  metadata: metadata,
                },
                options: request_options)
      end

      # List coupons, newest first.
      #
      # @param limit [Integer] page size, 1–100 (API default 20).
      # @param cursor [String] opaque cursor from a previous page.
      # @param request_options [Hash]
      # @return [Page<NombaObject>]
      def list(limit: OMIT, cursor: OMIT, request_options: {})
        request_page("/coupons", query: { limit: limit, cursor: cursor }, options: request_options)
      end
    end
  end
end
