# frozen_string_literal: true

require_relative "nombaone/version"
require_relative "nombaone/errors"
require_relative "nombaone/internal/util"
require_relative "nombaone/object"
require_relative "nombaone/pagination"
require_relative "nombaone/internal/http_client"
require_relative "nombaone/client"

# NombaOne — recurring billing for Nigeria over card, direct debit, bank
# transfer, and more, with dunning that recovers and a ledger that never loses
# a kobo. This module is the SDK's namespace and entrypoint.
#
# @example Construct a client
#   nombaone = Nombaone.new(ENV["NOMBAONE_API_KEY"])
#   customer = nombaone.customers.create(email: "ada@example.com", name: "Ada")
#
# @example Verify a webhook without a client (only the signing secret is needed)
#   event = Nombaone.webhooks.construct_event(raw_body, signature_header, secret)
module Nombaone
  # Construct a new API client.
  #
  # @param api_key [String, nil] your secret key (`nbo_sandbox_…` / `nbo_live_…`).
  #   Defaults to `ENV["NOMBAONE_API_KEY"]`.
  # @param options [Hash] see {Client#initialize} (`base_url:`, `timeout:`,
  #   `max_retries:`, `http:`, `default_headers:`).
  # @return [Nombaone::Client]
  def self.new(api_key = nil, **options)
    Client.new(api_key, **options)
  end
end
