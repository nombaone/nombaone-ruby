# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0]

Initial release — the official Ruby SDK for the NombaOne subscription-billing
API.

### Added

- `Nombaone::Client` covering the full API surface: customers, plans (with
  nested prices), prices, subscriptions (with schedules and dunning), invoices,
  coupons, payment methods, mandates, settlements, webhook endpoints (with
  deliveries), events, organization (with billing policy), metrics, and the
  sandbox toolkit.
- Automatic, money-safe idempotency: a UUID `Idempotency-Key` is generated once
  per POST and reused across every automatic retry, so a network blip can never
  double-charge.
- Automatic retries with full-jitter exponential backoff, honoring `Retry-After`,
  for transport failures, timeouts, 408/429/5xx, and in-flight idempotency
  conflicts.
- Typed error hierarchy (`Nombaone::APIError` and subclasses) carrying the wire
  `code`, `hint`, `doc_url`, per-field validation errors, and `request_id`.
- Cursor pagination with idiomatic auto-iteration (`Enumerable`, `each`,
  `auto_paging_each`) plus manual cursor control.
- A keyless webhook helper (`Nombaone.webhooks`) implementing signed-delivery
  verification, event construction, and test-header generation.
- Zero runtime dependencies; RBS type signatures shipped in `sig/`.

[Unreleased]: https://github.com/nombaone/nomba-ruby/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/nombaone/nomba-ruby/releases/tag/v0.1.0
