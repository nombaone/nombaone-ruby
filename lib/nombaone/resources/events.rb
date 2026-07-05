# frozen_string_literal: true

module Nombaone
  module Resources
    # Events — the append-only log behind every webhook. Webhook delivery is
    # at-least-once; this log is your reconciliation backstop when a delivery
    # was missed or you need to backfill.
    class Events < BaseResource
      # List events, newest first.
      #
      # @param type [String] filter to one catalog type, e.g. `"invoice.paid"`.
      # @param limit [Integer] page size, 1–100 (API default 20).
      # @param cursor [String] opaque cursor from a previous page.
      # @param request_options [Hash]
      # @return [Page<NombaObject>]
      #
      # @example
      #   nombaone.events.list(type: "invoice.paid").each { |event| puts event.id }
      def list(type: OMIT, limit: OMIT, cursor: OMIT, request_options: {})
        request_page("/events",
                     query: { type: type, limit: limit, cursor: cursor },
                     options: request_options)
      end

      # Retrieve one event by id.
      #
      # @param id [String] `nbo…evt`
      # @param request_options [Hash]
      # @return [NombaObject]
      def retrieve(id, request_options: {})
        request(:get, "/events/#{encode(id)}", options: request_options)
      end

      # The machine-readable event catalog — every event type the platform can
      # emit, with a description and its `data` keys. Useful for building
      # subscription pickers or codegen.
      #
      # @param request_options [Hash]
      # @return [NombaObject] a map of `type => { when:, payload: }`; read entries
      #   with `catalog["invoice.paid"]`.
      def catalog(request_options: {})
        request(:get, "/events/catalog", options: request_options)
      end
    end
  end
end
