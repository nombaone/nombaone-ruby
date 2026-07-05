# frozen_string_literal: true

module Nombaone
  module Resources
    # Deliveries under a webhook endpoint: inspect and replay
    # (`nombaone.webhook_endpoints.deliveries`).
    class WebhookEndpointDeliveries < BaseResource
      # List an endpoint's deliveries, newest first.
      #
      # @param endpoint_id [String] `nbo…whk`
      # @param status [String] `"pending"`, `"succeeded"`, `"failed"`, `"dead"`.
      # @param event_type [String] filter by catalog event type.
      # @param endpoint [String] filter by endpoint reference.
      # @param limit [Integer] page size, 1–100 (API default 20).
      # @param cursor [String] opaque cursor from a previous page.
      # @param request_options [Hash]
      # @return [Page<NombaObject>]
      def list(endpoint_id, status: OMIT, event_type: OMIT, endpoint: OMIT, limit: OMIT,
               cursor: OMIT, request_options: {})
        request_page("/webhooks/#{encode(endpoint_id)}/deliveries",
                     query: {
                       status: status,
                       event_type: event_type,
                       endpoint: endpoint,
                       limit: limit,
                       cursor: cursor,
                     },
                     options: request_options)
      end

      # Retrieve one delivery.
      #
      # @param endpoint_id [String] `nbo…whk`
      # @param delivery_id [String] `nbo…whd`
      # @param request_options [Hash]
      # @return [NombaObject]
      def retrieve(endpoint_id, delivery_id, request_options: {})
        request(:get, "/webhooks/#{encode(endpoint_id)}/deliveries/#{encode(delivery_id)}",
                options: request_options)
      end

      # Redeliver a past delivery. The **original event id is kept**, so a
      # receiver that dedupes on `event.event.id` correctly treats it as
      # already-seen.
      #
      # @param endpoint_id [String] `nbo…whk`
      # @param delivery_id [String] `nbo…whd`
      # @param request_options [Hash]
      # @return [NombaObject]
      def replay(endpoint_id, delivery_id, request_options: {})
        request(:post, "/webhooks/#{encode(endpoint_id)}/deliveries/#{encode(delivery_id)}/replay",
                body: {}, options: request_options)
      end
    end

    # Webhook endpoints — register and manage the URLs that receive signed
    # events. To *verify* incoming deliveries in your handler, use
    # {Nombaone.webhooks} / {Nombaone::Webhooks#construct_event} — the crypto
    # helper, not this REST resource.
    class WebhookEndpoints < BaseResource
      # Deliveries under an endpoint.
      # @return [WebhookEndpointDeliveries]
      def deliveries
        @deliveries ||= WebhookEndpointDeliveries.new(@client)
      end

      # Register an endpoint. The response includes the full `signing_secret`
      # **exactly once** — store it in your secret manager immediately.
      #
      # @param url [String]
      # @param enabled_events [Array<String>] event types to fan out; defaults to
      #   `["*"]` (all events) server-side.
      # @param request_options [Hash]
      # @return [NombaObject] the endpoint plus its one-time `signing_secret`.
      #
      # @example
      #   endpoint = nombaone.webhook_endpoints.create(
      #     url: "https://example.com/nombaone/webhooks",
      #     enabled_events: ["invoice.paid", "invoice.payment_failed"]
      #   )
      #   store_secret(endpoint.signing_secret)
      def create(url:, enabled_events: OMIT, request_options: {})
        request(:post, "/webhooks",
                body: { url: url, enabled_events: enabled_events }, options: request_options)
      end

      # Retrieve an endpoint by id.
      #
      # @param id [String] `nbo…whk`
      # @param request_options [Hash]
      # @return [NombaObject]
      # @raise [Nombaone::NotFoundError] 404 `WEBHOOK_ENDPOINT_NOT_FOUND`
      def retrieve(id, request_options: {})
        request(:get, "/webhooks/#{encode(id)}", options: request_options)
      end

      # Update url, event subscription, or enabled state.
      #
      # @param id [String] `nbo…whk`
      # @param url [String]
      # @param enabled_events [Array<String>]
      # @param disabled [Boolean] `true` pauses deliveries; `false` re-enables.
      # @param request_options [Hash]
      # @return [NombaObject]
      def update(id, url: OMIT, enabled_events: OMIT, disabled: OMIT, request_options: {})
        request(:patch, "/webhooks/#{encode(id)}",
                body: { url: url, enabled_events: enabled_events, disabled: disabled },
                options: request_options)
      end

      # List your endpoints.
      #
      # @param request_options [Hash]
      # @return [Page<NombaObject>]
      def list(request_options: {})
        request_page("/webhooks", options: request_options)
      end

      # Delete an endpoint. Pending deliveries to it are retired.
      #
      # @param id [String] `nbo…whk`
      # @param request_options [Hash]
      # @return [NombaObject]
      def delete(id, request_options: {})
        request(:delete, "/webhooks/#{encode(id)}", options: request_options)
      end

      # Rotate the signing secret. The new secret is returned **exactly once**;
      # the old one is briefly honored so you can roll without dropping in-flight
      # deliveries.
      #
      # @param id [String] `nbo…whk`
      # @param request_options [Hash]
      # @return [NombaObject] with the new one-time `signing_secret`.
      def rotate_secret(id, request_options: {})
        request(:post, "/webhooks/#{encode(id)}/rotate-secret", body: {}, options: request_options)
      end
    end
  end
end
