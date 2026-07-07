# frozen_string_literal: true

require_relative "lib/nombaone/version"

Gem::Specification.new do |spec|
  spec.name = "nombaone"
  spec.version = Nombaone::VERSION
  spec.authors = ["Nomba One"]
  spec.email = ["developers@nombaone.xyz"]

  spec.summary = "The official Ruby SDK for the NombaOne subscription-billing API."
  spec.description = <<~DESC.tr("\n", " ").strip
    Recurring billing for Nigeria over card, direct debit, bank transfer, and
    more — with dunning that recovers, idempotency that can never double-charge,
    and a ledger that never loses a kobo. Zero runtime dependencies.
  DESC
  spec.homepage = "https://nombaone.xyz"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "https://github.com/nombaone/nombaone-ruby",
    "changelog_uri" => "https://github.com/nombaone/nombaone-ruby/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/nombaone/nombaone-ruby/issues",
    "documentation_uri" => "https://docs.nombaone.xyz",
    "rubygems_mfa_required" => "true",
  }

  spec.files = Dir[
    "lib/**/*.rb",
    "sig/**/*.rbs",
    "README.md",
    "CHANGELOG.md",
    "LICENSE",
  ]
  spec.require_paths = ["lib"]

  # Zero runtime dependencies — the SDK is built entirely on the Ruby standard
  # library (net/http, json, openssl, securerandom, uri, cgi).
end
