# frozen_string_literal: true

module Nombaone
  module Resources
    # Prices nested under a plan (create/list); reach `nombaone.prices` for
    # reads and deactivation.
    class PlanPrices < BaseResource
      # Create a price under a plan. Prices are immutable once created.
      #
      # @param plan_id [String] `nbo…pln`
      # @param unit_amount_in_kobo [Integer] amount per unit per interval,
      #   **integer kobo** (₦1.00 = 100). `250_000` is ₦2,500 — not ₦250,000.
      # @param interval [String] `"day"` `"week"` `"month"` `"year"`.
      # @param interval_count [Integer] bill every N intervals (default 1).
      # @param usage_type [String] `"licensed"` (default) or `"metered"`.
      # @param billing_scheme [String] `"per_unit"` (default) or `"tiered"`.
      # @param trial_period_days [Integer] free-trial days at subscribe time.
      # @param metadata [Hash]
      # @param request_options [Hash]
      # @return [NombaObject]
      #
      # @example
      #   price = nombaone.plans.prices.create(plan.id, unit_amount_in_kobo: 250_000, interval: "month")
      def create(plan_id, unit_amount_in_kobo:, interval:, interval_count: OMIT, usage_type: OMIT,
                 billing_scheme: OMIT, trial_period_days: OMIT, metadata: OMIT, request_options: {})
        request(:post, "/plans/#{encode(plan_id)}/prices",
                body: {
                  unit_amount_in_kobo: unit_amount_in_kobo,
                  interval: interval,
                  interval_count: interval_count,
                  usage_type: usage_type,
                  billing_scheme: billing_scheme,
                  trial_period_days: trial_period_days,
                  metadata: metadata,
                },
                options: request_options)
      end

      # List a plan's prices, newest first.
      #
      # @param plan_id [String] `nbo…pln`
      # @param limit [Integer] page size, 1–100 (API default 20).
      # @param cursor [String] opaque cursor from a previous page.
      # @param request_options [Hash]
      # @return [Page<NombaObject>]
      def list(plan_id, limit: OMIT, cursor: OMIT, request_options: {})
        request_page("/plans/#{encode(plan_id)}/prices",
                     query: { limit: limit, cursor: cursor }, options: request_options)
      end
    end

    # Plans — your catalog. A plan holds the name and description; its prices
    # (amount + cadence) live underneath it (`nombaone.plans.prices`).
    #
    # @example
    #   plan = nombaone.plans.create(name: "Pro")
    #   price = nombaone.plans.prices.create(plan.id, unit_amount_in_kobo: 250_000, interval: "month")
    class Plans < BaseResource
      # Prices nested under a plan.
      # @return [PlanPrices]
      def prices
        @prices ||= PlanPrices.new(@client)
      end

      # Create a plan.
      #
      # @param name [String] unique within your organization (`PLAN_NAME_TAKEN` on reuse).
      # @param description [String]
      # @param metadata [Hash]
      # @param request_options [Hash]
      # @return [NombaObject]
      # @raise [Nombaone::ConflictError] 409 `PLAN_NAME_TAKEN`
      def create(name:, description: OMIT, metadata: OMIT, request_options: {})
        request(:post, "/plans",
                body: { name: name, description: description, metadata: metadata },
                options: request_options)
      end

      # Retrieve a plan by id.
      #
      # @param id [String] `nbo…pln`
      # @param request_options [Hash]
      # @return [NombaObject]
      # @raise [Nombaone::NotFoundError] 404 `PLAN_NOT_FOUND`
      def retrieve(id, request_options: {})
        request(:get, "/plans/#{encode(id)}", options: request_options)
      end

      # Update a plan's mutable fields. At least one field is required.
      #
      # @param id [String] `nbo…pln`
      # @param name [String]
      # @param description [String, nil] pass `nil` to clear the description.
      # @param metadata [Hash]
      # @param request_options [Hash]
      # @return [NombaObject]
      def update(id, name: OMIT, description: OMIT, metadata: OMIT, request_options: {})
        request(:patch, "/plans/#{encode(id)}",
                body: { name: name, description: description, metadata: metadata },
                options: request_options)
      end

      # List plans, newest first.
      #
      # @param status [String] `"active"` or `"archived"`.
      # @param limit [Integer] page size, 1–100 (API default 20).
      # @param cursor [String] opaque cursor from a previous page.
      # @param request_options [Hash]
      # @return [Page<NombaObject>]
      def list(status: OMIT, limit: OMIT, cursor: OMIT, request_options: {})
        request_page("/plans",
                     query: { status: status, limit: limit, cursor: cursor },
                     options: request_options)
      end

      # Archive a plan — it stops being subscribable but its history stays.
      #
      # @param id [String] `nbo…pln`
      # @param request_options [Hash]
      # @return [NombaObject]
      # @raise [Nombaone::ConflictError] 409 `PLAN_ALREADY_ARCHIVED`
      # @raise [Nombaone::ConflictError] 409 `PLAN_HAS_ACTIVE_SUBSCRIBERS` —
      #   migrate or cancel those subscriptions first.
      def archive(id, request_options: {})
        request(:post, "/plans/#{encode(id)}/archive", body: {}, options: request_options)
      end
    end
  end
end
