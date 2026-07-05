# frozen_string_literal: true

module Nombaone
  # The API resource namespaces (`nombaone.customers`, `nombaone.subscriptions`,
  # …). Each is a thin, fully-documented transcription of one slice of the wire
  # contract.
  module Resources
    # Re-exported so resource method signatures can default optional keyword
    # arguments to `OMIT` (dropped from the body) rather than `nil` (sent as
    # JSON `null` to clear a nullable field). See {Nombaone::Internal::OMIT}.
    OMIT = Internal::OMIT

    # Base class every resource namespace extends. Holds the client and the
    # small request helpers each method builds on.
    class BaseResource
      # @api private
      def initialize(client)
        @client = client
      end

      private

      # Issue a single-object request; returns a {NombaObject}.
      def request(method, path, body: nil, query: nil, options: {})
        @client.request(method: method, path: path, body: body, query: query, options: options)
      end

      # Issue a list request; returns a {Page}.
      def request_page(path, query: nil, options: {})
        @client.request_page(method: :get, path: path, query: query, options: options)
      end

      # Percent-encode one id before splicing it into a path — ids come from
      # user input and are never trusted raw.
      def encode(value)
        Internal::Util.encode_path_segment(value)
      end
    end
  end
end
