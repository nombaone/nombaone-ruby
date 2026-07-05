# frozen_string_literal: true

RSpec.describe Nombaone::Client do
  describe "construction and key → host derivation" do
    it "derives the sandbox host from an nbo_sandbox_ key" do
      client = described_class.new("nbo_sandbox_abc")
      expect(client.mode).to eq("sandbox")
      expect(client.base_url).to eq("https://sandbox.api.nombaone.xyz")
    end

    it "derives the live host from an nbo_live_ key" do
      client = described_class.new("nbo_live_abc")
      expect(client.mode).to eq("live")
      expect(client.base_url).to eq("https://api.nombaone.xyz")
    end

    it "lets an explicit base_url win and strips trailing slashes" do
      client = described_class.new("nbo_sandbox_abc", base_url: "http://localhost:8611/")
      expect(client.base_url).to eq("http://localhost:8611")
    end

    it "falls back to ENV['NOMBAONE_API_KEY'] when no key is passed" do
      original = ENV.fetch("NOMBAONE_API_KEY", nil)
      ENV["NOMBAONE_API_KEY"] = "nbo_live_from_env"
      expect(described_class.new.mode).to eq("live")
    ensure
      ENV["NOMBAONE_API_KEY"] = original
    end

    it "raises a helpful error when the key is missing" do
      original = ENV.fetch("NOMBAONE_API_KEY", nil)
      ENV.delete("NOMBAONE_API_KEY")
      expect { described_class.new(nil) }.to raise_error(Nombaone::Error, /Missing API key/)
    ensure
      ENV["NOMBAONE_API_KEY"] = original
    end

    it "raises for an unrecognized key prefix unless base_url is given" do
      expect do
        described_class.new("weird_key")
      end.to raise_error(Nombaone::Error, /Unrecognized API key/)
      expect { described_class.new("weird_key", base_url: "http://api.test") }.not_to raise_error
    end
  end

  describe "the wire request it builds" do
    it "sends Bearer auth, JSON accept, and the SDK User-Agent" do
      mock = mock_connection
      mock.ok({})
      build_client(mock).request(method: :get, path: "/customers")

      headers = mock.calls.first.headers
      expect(headers["authorization"]).to eq("Bearer #{SpecSupport::ClientHelpers::SANDBOX_KEY}")
      expect(headers["accept"]).to eq("application/json")
      expect(headers["user-agent"]).to eq("nombaone-ruby/#{Nombaone::VERSION}")
    end

    it "prefixes /v1 exactly once and serializes snake params to camelCase query" do
      mock = mock_connection
      mock.ok([])
      build_client(mock).request(method: :get, path: "/customers",
                                 query: { customer_id: "nbo1", limit: 20 })

      expect(mock.calls.first.url).to eq("http://api.test/v1/customers?customerId=nbo1&limit=20")
    end

    it "sends a JSON body with camelCase keys and a content-type on writes" do
      mock = mock_connection
      mock.ok({})
      build_client(mock).request(method: :post, path: "/customers",
                                 body: { email: "a@b.co", amount_in_kobo: 100 })

      call = mock.calls.first
      expect(call.headers["content-type"]).to eq("application/json")
      expect(call.body).to eq("email" => "a@b.co", "amountInKobo" => 100)
    end

    it "sends default and per-call headers, with per-call winning" do
      mock = mock_connection
      mock.ok({})
      client = build_client(mock, default_headers: { "X-Trace" => "base", "X-Keep" => "yes" })
      client.request(method: :get, path: "/customers",
                     options: { headers: { "X-Trace" => "call" } })

      headers = mock.calls.first.headers
      expect(headers["x-trace"]).to eq("call")
      expect(headers["x-keep"]).to eq("yes")
    end

    it "unwraps the envelope data into a NombaObject carrying the request id" do
      mock = mock_connection
      mock.ok({ "id" => "nbo000000000001cus", "email" => "a@b.co" }, request_id: "req_42")
      result = build_client(mock).request(method: :get, path: "/customers/x")

      expect(result).to be_a(Nombaone::NombaObject)
      expect(result.id).to eq("nbo000000000001cus")
      expect(result.request_id).to eq("req_42")
    end

    it "raises a ServerError when the body is not a valid envelope" do
      mock = mock_connection
      mock.respond(200, { not: "an envelope" })
      expect { build_client(mock).request(method: :get, path: "/x") }
        .to raise_error(Nombaone::APIError, /not a valid NombaOne envelope/)
    end
  end
end
