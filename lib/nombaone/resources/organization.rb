# frozen_string_literal: true

module Nombaone
  module Resources
    # Billing + dunning policy under `nombaone.organization.billing`.
    class OrganizationBilling < BaseResource
      # Read the org's billing + dunning policy.
      #
      # @param request_options [Hash]
      # @return [NombaObject]
      def retrieve(request_options: {})
        request(:get, "/organization/billing", options: request_options)
      end

      # Update the billing policy. PUT semantics, but only supplied keys change.
      #
      # @param partial_collection_enabled [Boolean]
      # @param proration_credit_policy [String] `"credit_next_cycle"` or `"none"`.
      # @param dunning_max_attempts [Integer] 1–10.
      # @param dunning_intervals_hours [Array<Integer>]
      # @param dunning_max_window_hours [Integer] must be ≥ the largest interval.
      # @param grace_period_hours [Integer]
      # @param payday_days [Array<Integer>] days of month, 1–31.
      # @param payday_pull_forward_days [Integer] 0–28.
      # @param payday_bias_enabled [Boolean]
      # @param default_collection_method [String] `"charge_automatically"` or `"send_invoice"`.
      # @param comms_enabled [Boolean]
      # @param request_options [Hash]
      # @return [NombaObject]
      #
      # @example
      #   nombaone.organization.billing.update(payday_bias_enabled: true, payday_days: [25, 28, 30])
      def update(partial_collection_enabled: OMIT, proration_credit_policy: OMIT,
                 dunning_max_attempts: OMIT, dunning_intervals_hours: OMIT,
                 dunning_max_window_hours: OMIT, grace_period_hours: OMIT, payday_days: OMIT,
                 payday_pull_forward_days: OMIT, payday_bias_enabled: OMIT,
                 default_collection_method: OMIT, comms_enabled: OMIT, request_options: {})
        request(:put, "/organization/billing",
                body: {
                  partial_collection_enabled: partial_collection_enabled,
                  proration_credit_policy: proration_credit_policy,
                  dunning_max_attempts: dunning_max_attempts,
                  dunning_intervals_hours: dunning_intervals_hours,
                  dunning_max_window_hours: dunning_max_window_hours,
                  grace_period_hours: grace_period_hours,
                  payday_days: payday_days,
                  payday_pull_forward_days: payday_pull_forward_days,
                  payday_bias_enabled: payday_bias_enabled,
                  default_collection_method: default_collection_method,
                  comms_enabled: comms_enabled,
                },
                options: request_options)
      end
    end

    # Organization settings — configuration, not a billing object.
    class Organization < BaseResource
      # Billing + dunning policy.
      # @return [OrganizationBilling]
      def billing
        @billing ||= OrganizationBilling.new(@client)
      end

      # Read org-level settings (limits, settlement mode, branding, statuses).
      #
      # @param request_options [Hash]
      # @return [NombaObject]
      def retrieve(request_options: {})
        request(:get, "/organization", options: request_options)
      end

      # Update tenant-editable settings. At least one field is required.
      #
      # @param monthly_request_quota [Integer]
      # @param settlement_mode [String] `"split_at_collection"` or `"collect_then_payout"`.
      # @param branding [Hash] `display_name`, `support_email`, `logo_url`, `primary_color_hex`.
      # @param request_options [Hash]
      # @return [NombaObject]
      def update(monthly_request_quota: OMIT, settlement_mode: OMIT, branding: OMIT,
                 request_options: {})
        request(:put, "/organization",
                body: {
                  monthly_request_quota: monthly_request_quota,
                  settlement_mode: settlement_mode,
                  branding: branding,
                },
                options: request_options)
      end
    end
  end
end
