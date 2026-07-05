# frozen_string_literal: true

module Nombaone
  module Resources
    # Prices — the amounts and cadences plans are sold at. Create and list them
    # under a plan via `nombaone.plans.prices`; this namespace reads and
    # deactivates them directly.
    #
    # Prices are **immutable** once created — to change pricing, create a new
    # price and deactivate the old one. Existing subscriptions keep the price
    # they were sold at.
    class Prices < BaseResource
      # Retrieve a price by id.
      #
      # @param id [String] `nbo…prc`
      # @param request_options [Hash]
      # @return [NombaObject]
      # @raise [Nombaone::NotFoundError] 404 `PRICE_NOT_FOUND`
      def retrieve(id, request_options: {})
        request(:get, "/prices/#{encode(id)}", options: request_options)
      end

      # List prices across all plans, newest first.
      #
      # @param plan_ref [String] filter to one plan's prices (`nbo…pln`). Note
      #   the wire filter name is `planRef`.
      # @param active [Boolean] filter by the active flag.
      # @param limit [Integer] page size, 1–100 (API default 20).
      # @param cursor [String] opaque cursor from a previous page.
      # @param request_options [Hash]
      # @return [Page<NombaObject>]
      #
      # @example
      #   page = nombaone.prices.list(plan_ref: plan.id, active: true)
      def list(plan_ref: OMIT, active: OMIT, limit: OMIT, cursor: OMIT, request_options: {})
        request_page("/prices",
                     query: { plan_ref: plan_ref, active: active, limit: limit, cursor: cursor },
                     options: request_options)
      end

      # Deactivate a price so no new subscriptions can be created against it.
      # Existing subscriptions are unaffected — prices are immutable history.
      #
      # @param id [String] `nbo…prc`
      # @param request_options [Hash]
      # @return [NombaObject]
      # @raise [Nombaone::ConflictError] 409 `PRICE_ALREADY_INACTIVE`
      def deactivate(id, request_options: {})
        request(:post, "/prices/#{encode(id)}/deactivate", body: {}, options: request_options)
      end
    end
  end
end
