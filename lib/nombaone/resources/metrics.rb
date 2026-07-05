# frozen_string_literal: true

module Nombaone
  module Resources
    # Metrics — MRR, churn, and the dunning funnel, computed from the ledger on
    # read (never stored, never stale).
    class Metrics < BaseResource
      # Billing KPIs over a window (defaults to a recent window server-side).
      #
      # @param from [String] ISO-8601 date-time, start of the window.
      # @param to [String] ISO-8601 date-time, end of the window.
      # @param request_options [Hash]
      # @return [NombaObject] with `mrr_in_kobo`, `active_count`, churn counts,
      #   and the `dunning_funnel`.
      #
      # @example
      #   metrics = nombaone.metrics.billing
      #   puts "MRR ₦#{metrics.mrr_in_kobo / 100}"
      def billing(from: OMIT, to: OMIT, request_options: {})
        request(:get, "/metrics/billing", query: { from: from, to: to }, options: request_options)
      end
    end
  end
end
