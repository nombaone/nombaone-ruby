# frozen_string_literal: true

module Nombaone
  # The NombaOne API client. Construct one with your secret key; it derives the
  # host from the key's prefix and exposes every resource as a namespace.
  #
  # @example
  #   nombaone = Nombaone.new(ENV["NOMBAONE_API_KEY"])
  #
  #   plan = nombaone.plans.create(name: "Pro")
  #   price = nombaone.plans.prices.create(plan.id, unit_amount_in_kobo: 250_000, interval: "month")
  #   customer = nombaone.customers.create(email: "ada@example.com", name: "Ada Lovelace")
  #   method = nombaone.sandbox.create_payment_method(customer_id: customer.id)
  #   subscription = nombaone.subscriptions.create(
  #     customer_id: customer.id, price_id: price.id, payment_method_id: method.id
  #   )
  #   subscription.status # => "active"
  class Client
    # Default host per environment. Overridable with the `base_url:` option.
    BASE_URLS = {
      "sandbox" => "https://sandbox.api.nombaone.xyz",
      "live" => "https://api.nombaone.xyz",
    }.freeze

    # Per-attempt request timeout, in seconds.
    DEFAULT_TIMEOUT = 30
    # Automatic retries (3 attempts total). Retried POSTs reuse one idempotency key.
    DEFAULT_MAX_RETRIES = 2

    # @return [String] the environment this client talks to ("sandbox"/"live"),
    #   derived from the key prefix.
    attr_reader :mode
    # @return [String] the API origin in use (no `/v1`).
    attr_reader :base_url

    # @param api_key [String, nil] your secret key (`nbo_sandbox_…` / `nbo_live_…`).
    #   Defaults to `ENV["NOMBAONE_API_KEY"]`. Server-side only — never ship it
    #   to a browser or mobile app.
    # @param base_url [String, nil] override the API origin (no `/v1`). Defaults
    #   to the host matching the key's environment; required if the key prefix
    #   is unrecognized.
    # @param timeout [Numeric] per-attempt timeout in seconds (default 30).
    # @param max_retries [Integer] automatic retry budget (default 2).
    # @param http [#execute, nil] an injectable connection for tests/proxies;
    #   defaults to a `Net::HTTP` transport.
    # @param default_headers [Hash{String => String}, nil] extra headers on
    #   every request.
    # @raise [Nombaone::Error] if the key is missing or its prefix is
    #   unrecognized and no `base_url` was given.
    def initialize(api_key = nil, base_url: nil, timeout: DEFAULT_TIMEOUT,
                   max_retries: DEFAULT_MAX_RETRIES, http: nil, default_headers: nil, sleeper: nil)
      resolved_key = api_key || ENV.fetch("NOMBAONE_API_KEY", nil)
      if resolved_key.nil? || resolved_key.empty?
        raise Error,
              "Missing API key — set the NOMBAONE_API_KEY environment variable, or pass one: " \
              'Nombaone.new("nbo_sandbox_…"). Create keys in the dashboard under API keys.'
      end

      derived = derive_mode(resolved_key)
      if derived.nil? && base_url.nil?
        raise Error,
              'Unrecognized API key format — expected a key starting with "nbo_sandbox_" or ' \
              '"nbo_live_". Copy the key exactly as shown in the dashboard, or pass an explicit ' \
              "base_url: if you are targeting a custom host."
      end

      @mode = derived || "sandbox"
      @base_url = (base_url || BASE_URLS.fetch(@mode)).sub(%r{/+\z}, "")
      @http = Internal::HTTPClient.new(
        api_key: resolved_key,
        base_url: @base_url,
        timeout: timeout,
        max_retries: max_retries,
        connection: http || Internal::NetHTTPConnection.new,
        default_headers: default_headers,
        sleeper: sleeper,
      )
    end

    # @return [Resources::Customers] the people and businesses you bill.
    def customers = @customers ||= Resources::Customers.new(self)
    # @return [Resources::Plans] your catalog (prices nest under `plans.prices`).
    def plans = @plans ||= Resources::Plans.new(self)
    # @return [Resources::Prices] immutable amounts and cadences.
    def prices = @prices ||= Resources::Prices.new(self)
    # @return [Resources::Subscriptions] the core billing object.
    def subscriptions = @subscriptions ||= Resources::Subscriptions.new(self)
    # @return [Resources::Invoices] what billing cycles produced (read + void).
    def invoices = @invoices ||= Resources::Invoices.new(self)
    # @return [Resources::Coupons] reusable discount rules.
    def coupons = @coupons ||= Resources::Coupons.new(self)
    # @return [Resources::PaymentMethods] cards, mandates, virtual accounts.
    def payment_methods = @payment_methods ||= Resources::PaymentMethods.new(self)
    # @return [Resources::Mandates] direct-debit mandates (async NIBSS consent).
    def mandates = @mandates ||= Resources::Mandates.new(self)
    # @return [Resources::Settlements] settlements, refunds, payouts, escrow.
    def settlements = @settlements ||= Resources::Settlements.new(self)
    # @return [Resources::WebhookEndpoints] webhook endpoint management (REST).
    def webhook_endpoints = @webhook_endpoints ||= Resources::WebhookEndpoints.new(self)
    # @return [Resources::Events] the domain-event log — your reconciliation backstop.
    def events = @events ||= Resources::Events.new(self)
    # @return [Resources::Organization] org settings + billing/dunning policy.
    def organization = @organization ||= Resources::Organization.new(self)
    # @return [Resources::Metrics] billing KPIs computed from the ledger.
    def metrics = @metrics ||= Resources::Metrics.new(self)
    # @return [Resources::Sandbox] sandbox-only simulation instruments.
    def sandbox = @sandbox ||= Resources::Sandbox.new(self)

    # A {Webhooks} helper bound to this client. Verification needs only the
    # signing secret, so {Nombaone.webhooks} works without a client too.
    #
    # @return [Nombaone::Webhooks]
    def webhooks = @webhooks ||= Webhooks.new

    # Execute a single-object request and return the wrapped {NombaObject}.
    # @api private
    def request(method:, path:, query: nil, body: nil, options: nil)
      result = perform(method: method, path: path, query: query, body: body, options: options)
      wrap_data(result)
    end

    # Execute a list request and return a {Page} that auto-paginates.
    # @api private
    def request_page(method:, path:, query: nil, options: nil)
      raw_query = query || {}
      fetcher = lambda do |query_for_page|
        perform(method: method, path: path, query: query_for_page, options: options)
      end
      Page.new(fetcher: fetcher, query: raw_query, result: fetcher.call(raw_query))
    end

    private

    def perform(method:, path:, query: nil, body: nil, options: nil)
      @http.request(
        method: method,
        path: path,
        query: query.nil? ? nil : Internal::Util.serialize_query(query),
        body: body.nil? ? nil : Internal::Util.serialize_body(body),
        options: options,
      )
    end

    def wrap_data(result)
      data = result.data
      return data unless data.is_a?(Hash)

      NombaObject.new(data, request_id: result.request_id, response: result.response)
    end

    def derive_mode(api_key)
      return "sandbox" if api_key.start_with?("nbo_sandbox_")
      return "live" if api_key.start_with?("nbo_live_")

      nil
    end
  end
end
