# frozen_string_literal: true

module SpecSupport
  # Helpers for building a client wired to a {MockConnection}. The injected
  # `sleeper` makes retry backoff instant and deterministic in tests.
  module ClientHelpers
    SANDBOX_KEY = "nbo_sandbox_unit_test_key"

    # A UUID v4-ish shape check for auto-generated idempotency keys.
    UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/

    def mock_connection
      SpecSupport::MockConnection.new
    end

    def build_client(connection, **options)
      Nombaone.new(
        SANDBOX_KEY,
        base_url: "http://api.test",
        http: connection,
        sleeper: ->(_seconds) {},
        **options,
      )
    end
  end
end

RSpec.configure do |config|
  config.include SpecSupport::ClientHelpers
end
