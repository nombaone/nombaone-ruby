# nombaone

The official Ruby SDK for the [Nomba One](https://nombaone.xyz) subscription-billing API — recurring billing for Nigeria over card, direct debit, bank transfer, and more, with dunning that recovers and a ledger that never loses a kobo.

```bash
gem install nombaone
# or add to your Gemfile:
gem "nombaone"
```

Requires Ruby 3.1+. Zero runtime dependencies (built on the standard library). Ships RBS type signatures.

## Quickstart

Grab a sandbox key (`nbo_sandbox_…`) from the [dashboard](https://app.nombaone.xyz), set it as `NOMBAONE_API_KEY`, and you are three objects away from a live subscription:

```ruby
require "nombaone"

nombaone = Nombaone.new(ENV["NOMBAONE_API_KEY"])

plan = nombaone.plans.create(name: "Pro")
price = nombaone.plans.prices.create(plan.id, unit_amount_in_kobo: 250_000, interval: "month") # ₦2,500/mo
customer = nombaone.customers.create(email: "ada@example.com", name: "Ada Lovelace")

# Sandbox: mint a deterministic test card, then subscribe.
method = nombaone.sandbox.create_payment_method(customer_id: customer.id)
subscription = nombaone.subscriptions.create(
  customer_id: customer.id,
  price_id: price.id,
  payment_method_id: method.id,
)

subscription.status # => "active"
```

The client derives the host from your key prefix — `nbo_sandbox_…` talks to `https://sandbox.api.nombaone.xyz`, `nbo_live_…` to `https://api.nombaone.xyz`. Server-side only; there is no publishable key to leak.

## Sandbox first

The sandbox runs the real billing engine. `nombaone.sandbox.*` gives you the levers to make a month happen in a second:

```ruby
# A card that declines like a thin balance does — "not yet", not "no".
nombaone.sandbox.create_payment_method(
  customer_id: customer.id,
  behavior: "decline_insufficient_funds", # or success | requires_otp | decline_expired_card | decline_do_not_honor
)

# The test clock: force the next billing cycle through the real engine.
cycle = nombaone.sandbox.advance_cycle(subscription.id)
cycle.outcome # => "paid" | "past_due" | …

# Fire a real, signed webhook at your registered endpoints.
nombaone.sandbox.simulate_webhook(type: "invoice.payment_failed")
```

These methods raise locally (before any network call) if used with a live key.

## Money is integer kobo

Every amount in the API is an **integer in kobo**: `₦1.00 = 100`. `250_000` is ₦2,500 — not ₦250,000. No floats, no decimal strings, `currency` is always `"NGN"`. Multiply naira by 100 exactly once, at the edge of your system; every money field is suffixed `_in_kobo` so a mixup is hard to type.

## Response objects

Every result is a lightweight object with snake_case readers derived from the wire's camelCase, plus bracket access and a `to_h` escape hatch:

```ruby
sub = nombaone.subscriptions.retrieve(id)
sub.status              # => "active"
sub.current_period_end  # from "currentPeriodEnd"
sub.items.first.price_id
sub[:latestInvoiceId]   # bracket access (snake or wire, String or Symbol)
sub.to_h                # the raw wire Hash
sub.request_id          # the meta.requestId for this call
```

## Pagination

Every `list` works three ways:

```ruby
# One page.
page = nombaone.invoices.list(status: "open", limit: 50)
page.data          # the items on this page
page.has_more?
page.next_cursor

# Manual paging.
page = page.next_page if page.next_page?

# Or let the SDK thread the cursors — a Page is Enumerable, and iteration is
# lazy (first(3) only fetches what it needs):
nombaone.invoices.list(status: "open").each do |invoice|
  # every item across every page
end
recent = nombaone.customers.list.first(3)
```

## Errors are a feature

Failures raise typed errors carrying everything the API said — the stable `code` to branch on, a `hint` telling you exactly what to do next, a `doc_url` into the error reference, per-field details on validation failures, and the `request_id` to quote to support:

```ruby
begin
  nombaone.subscriptions.create(customer_id: customer_id, price_id: price_id)
rescue Nombaone::ValidationError => e
  e.fields   # { "paymentMethodId" => [...] }
rescue Nombaone::RateLimitError => e
  e.retry_after # seconds
rescue Nombaone::NotFoundError => e
  e.code     # "CUSTOMER_NOT_FOUND"
end
```

| Status | Class                    | Notes                                     |
| ------ | ------------------------ | ----------------------------------------- |
| 400    | `BadRequestError`        | malformed request                         |
| 401    | `AuthenticationError`    | missing/invalid/wrong-environment key     |
| 403    | `PermissionDeniedError`  | missing scope, foreign resource           |
| 404    | `NotFoundError`          | wrong id or wrong environment             |
| 409    | `ConflictError`          | state conflicts, idempotency reuse        |
| 422    | `ValidationError`        | `error.fields` has the per-field messages |
| 429    | `RateLimitError`         | `retry_after`, `limit`, `remaining`       |
| 5xx    | `ServerError`            | safe to retry (the SDK already did)       |
| —      | `ConnectionError` / `TimeoutError` | transport-level                 |

All of them descend from `Nombaone::Error`, and webhook failures raise `Nombaone::WebhookVerificationError`. Branch on `e.code` (stable) or the class; the error codes are available as constants (`Nombaone::ErrorCode::CUSTOMER_NOT_FOUND`), and unknown future codes still parse.

## Idempotency & retries

The SDK auto-generates an `Idempotency-Key` for every POST and **reuses it across its automatic retries** (network failures, timeouts, 408/429/5xx — 2 retries by default, honoring `Retry-After`), so a blip can never double-charge. Pass your own key when the operation must stay idempotent across _process_ restarts:

```ruby
nombaone.settlements.create_payout(
  amount_in_kobo: 5_000_000, bank_code: "058", account_number: "0123456789",
  request_options: { idempotency_key: "payout-#{my_payout.id}" }, # ⚠ doubles as the payout's durable merchantTxRef
)
```

Every method also accepts `request_options:` with `:idempotency_key`, `:headers`, `:timeout`, `:max_retries`, and `:cancel_when` (a callable checked before each attempt — a caller cancel is never retried).

## Webhooks

Verify before you parse, and dedupe on the event id — delivery is at-least-once, never exactly-once. Verification needs only the signing secret, never an API key, so `Nombaone.webhooks` works in a receiver that never builds a client.

**Feed it the raw request body** — parsing and re-serializing JSON changes bytes and breaks the signature.

```ruby
# Rails
class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token

  def create
    event = Nombaone.webhooks.construct_event(
      request.raw_post,                                # the RAW body — never re-serialize
      request.headers["X-Nombaone-Signature"],
      ENV.fetch("NOMBAONE_WEBHOOK_SECRET"),            # shown once when you created the endpoint
    )

    return head(:ok) if already_processed?(event.event.id) # at-least-once ⇒ dedupe on event.event.id

    case event.type
    when Nombaone::WebhookEventType::INVOICE_PAID           then unlock(event.data.reference)
    when Nombaone::WebhookEventType::INVOICE_ACTION_REQUIRED then email(event.data.checkout_link)
    when Nombaone::WebhookEventType::INVOICE_PAYMENT_FAILED  then note(event.data.reason)
    end

    head :ok # respond 2xx fast; do heavy work async
  rescue Nombaone::WebhookVerificationError
    head :bad_request
  end
end
```

In **Sinatra/Rack**, the raw body is `request.body.read` and the header is `request.env["HTTP_X_NOMBAONE_SIGNATURE"]`. `construct_event` checks the `X-Nombaone-Signature` (`t=<unix>,v1=<hex>`, HMAC-SHA256 over `"#{t}.#{body}"`) in constant time, rejects stale timestamps (300s tolerance, configurable), and returns a typed event. `Nombaone.webhooks.generate_test_header(payload:, secret:)` lets you unit-test your handler. Manage endpoints via `nombaone.webhook_endpoints` (create/rotate return the secret **exactly once**).

## The full surface

`customers` (+credit, discount) · `plans` (+nested `prices`) · `prices` · `subscriptions` (pause/resume/cancel/resubscribe/change, `schedule`, `dunning`, upcoming invoice, events) · `invoices` · `coupons` · `payment_methods` (hosted-checkout cards, virtual accounts) · `mandates` (NIBSS direct debit) · `settlements` (escrow, refunds, payouts) · `webhook_endpoints` (+deliveries, replay) · `events` (+catalog) · `organization` (+billing policy) · `metrics` · `sandbox` — every operation in the [API reference](https://docs.nombaone.xyz), 1:1.

Worth knowing:

- **Mandates are asynchronous.** They start `consent_pending` and activate when the customer's bank confirms — listen for `payment_method.updated`, don't poll, don't charge early.
- **Bank transfer is a push rail.** `payment_methods.create_virtual_account` issues a NUBAN; collection completes when the transfer arrives and reconciles.
- **`past_due` is not canceled.** Read `nombaone.subscriptions.dunning.retrieve(id)` and honor `grace_access_until` before cutting anyone off. Involuntary churn is `status: "canceled"` with `cancellation_reason: "involuntary"` (and a `subscription.churned` event).
- **Prices are immutable; plans archive, never delete.**

## Configuration

```ruby
Nombaone.new(
  api_key,                 # defaults to ENV["NOMBAONE_API_KEY"]
  base_url: nil,           # override the derived host
  timeout: 30,             # per-attempt seconds
  max_retries: 2,          # automatic retry budget
  default_headers: {},     # sent on every request
  http: nil,               # inject a connection (tests, proxies)
)
```

Read-only `nombaone.mode` (`"sandbox"`/`"live"`, derived from the key) and `nombaone.base_url` are exposed.

## Examples & development

Runnable scripts live in [`examples/`](examples) — quickstart, pagination, the subscription lifecycle, a webhook receiver, and a dunning rehearsal with the test clock:

```bash
NOMBAONE_API_KEY=nbo_sandbox_… ruby -Ilib examples/01_quickstart.rb
```

To develop the SDK itself: `bundle install && rake` (RuboCop + RBS validate + specs). The live suite is opt-in:

```bash
NOMBAONE_INTEGRATION=1 NOMBAONE_API_KEY=nbo_sandbox_… \
  NOMBAONE_BASE_URL=https://sandbox.api.nombaone.xyz \
  bundle exec rspec spec/integration
```

## Requirements & versioning

Ruby ≥ 3.1. Semantic versioning; the API itself is versioned at `/v1` and additive changes never break you. MIT licensed.
