# frozen_string_literal: true

require "openssl"

RSpec.describe Nombaone::Webhooks do
  subject(:webhooks) { described_class.new }

  let(:secret) { "nbo_whsec_0123456789abcdef0123456789abcdef" }

  def event_body(overrides = {})
    JSON.generate({
      id: "nbo000000000001whd",
      type: "invoice.payment_failed",
      event: {
        id: "nbo000000000001evt",
        type: "invoice.payment_failed",
        createdAt: "2026-07-05T10:00:00.000Z",
      },
      data: { reference: "nbo000000000001inv", reason: "insufficient_funds" },
    }.merge(overrides))
  end

  def sign(payload, signing_secret = secret, timestamp = Time.now.to_i)
    v1 = OpenSSL::HMAC.hexdigest("SHA256", signing_secret, "#{timestamp}.#{payload}")
    "t=#{timestamp},v1=#{v1}"
  end

  describe "the golden vector (byte-for-byte)" do
    it "verifies the documented golden delivery" do
      golden_secret = "nbo_whsec_golden_0123456789abcdef0123456789abcdef"
      timestamp = 1_751_600_000
      payload = '{"id":"nbo000000000001whd","type":"invoice.paid","event":' \
                '{"id":"nbo000000000001evt","type":"invoice.paid",' \
                '"createdAt":"2026-07-04T10:00:00.000Z"},' \
                '"data":{"reference":"nbo000000000001inv"}}'
      header = "t=#{timestamp},v1=ba56a072beccddbc014a3f72ef1b4a30e2008b61dcbcca4ae2f16c7e4427b374"

      event = webhooks.construct_event(payload, header, golden_secret, tolerance: Float::INFINITY)
      expect(event.type).to eq("invoice.paid")
      expect(event.event.id).to eq("nbo000000000001evt")
      expect(event.data.reference).to eq("nbo000000000001inv")
    end

    it "matches HMAC-SHA256(secret, \"{t}.{body}\") hex exactly" do
      payload = '{"a":1}'
      timestamp = 1_751_600_000
      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{payload}")
      expect(
        webhooks.verify_signature(payload, "t=#{timestamp},v1=#{expected}", secret,
                                  tolerance: Float::INFINITY),
      ).to be(true)
    end
  end

  describe "#verify_signature" do
    it "accepts a correctly signed payload" do
      payload = event_body
      expect(webhooks.verify_signature(payload, sign(payload), secret)).to be(true)
    end

    it "rejects a tampered payload" do
      payload = event_body
      header = sign(payload)
      tampered = payload.sub("insufficient_funds", "do_not_honor")
      expect { webhooks.verify_signature(tampered, header, secret) }
        .to raise_error(Nombaone::WebhookVerificationError, /verification failed/)
    end

    it "rejects the wrong secret" do
      payload = event_body
      expect { webhooks.verify_signature(payload, sign(payload), "nbo_whsec_wrong") }
        .to raise_error(Nombaone::WebhookVerificationError)
    end

    it "rejects a stale timestamp beyond the 300s default tolerance" do
      payload = event_body
      stale = Time.now.to_i - 301
      expect { webhooks.verify_signature(payload, sign(payload, secret, stale), secret) }
        .to raise_error(Nombaone::WebhookVerificationError, /tolerance/)
    end

    it "rejects a future-dated timestamp symmetrically" do
      payload = event_body
      future = Time.now.to_i + 400
      expect { webhooks.verify_signature(payload, sign(payload, secret, future), secret) }
        .to raise_error(Nombaone::WebhookVerificationError, /tolerance/)
    end

    it "accepts a timestamp just inside tolerance and honors a custom tolerance" do
      payload = event_body
      fresh = Time.now.to_i - 290
      expect(webhooks.verify_signature(payload, sign(payload, secret, fresh), secret)).to be(true)

      old = Time.now.to_i - 400
      expect(
        webhooks.verify_signature(payload, sign(payload, secret, old), secret, tolerance: 600),
      ).to be(true)
    end

    it "accepts any matching v1 among several (secret rotation)" do
      payload = event_body
      timestamp = Time.now.to_i
      good = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{payload}")
      stale = OpenSSL::HMAC.hexdigest("SHA256", "nbo_whsec_old", "#{timestamp}.#{payload}")
      header = "t=#{timestamp},v1=#{stale},v1=#{good}"
      expect(webhooks.verify_signature(payload, header, secret)).to be(true)
    end

    it "raises distinct errors for missing header, malformed header, and missing secret" do
      payload = event_body
      expect { webhooks.verify_signature(payload, "", secret) }
        .to raise_error(Nombaone::WebhookVerificationError, /Missing X-Nombaone/)
      expect { webhooks.verify_signature(payload, "garbage", secret) }
        .to raise_error(Nombaone::WebhookVerificationError, /Malformed/)
      expect { webhooks.verify_signature(payload, "ate=1,vx=2", secret) }
        .to raise_error(Nombaone::WebhookVerificationError, /Malformed/)
      expect { webhooks.verify_signature(payload, sign(payload), "") }
        .to raise_error(Nombaone::WebhookVerificationError, /Missing signing secret/)
    end
  end

  describe "#construct_event" do
    it "verifies, then returns the typed event; type constants narrow it" do
      payload = event_body
      event = webhooks.construct_event(payload, sign(payload), secret)

      expect(event).to be_a(Nombaone::WebhookEvent)
      expect(event.event.id).to eq("nbo000000000001evt")
      expect(event.type).to eq(Nombaone::WebhookEventType::INVOICE_PAYMENT_FAILED)
      expect(event.data.reason).to eq("insufficient_funds")
    end

    it "synthesizes event.id from a flat legacy body so dedupe still works" do
      flat = JSON.generate(
        id: "evt_flat_1", type: "invoice.paid",
        createdAt: "2026-07-05T10:00:00.000Z", data: { reference: "nbo000000000001inv" }
      )
      event = webhooks.construct_event(flat, sign(flat), secret)
      expect(event.event.id).to eq("evt_flat_1")
      expect(event.event.type).to eq("invoice.paid")
    end

    it "rejects a non-JSON payload after the signature check" do
      payload = "not json"
      expect { webhooks.construct_event(payload, sign(payload), secret) }
        .to raise_error(Nombaone::WebhookVerificationError, /not valid JSON/)
    end

    it "round-trips with generate_test_header" do
      payload = event_body(type: "invoice.paid")
      header = webhooks.generate_test_header(payload: payload, secret: secret)
      event = webhooks.construct_event(payload, header, secret)
      expect(event.type).to eq("invoice.paid")
    end

    it "generate_test_header with an explicit old timestamp fails tolerance (proves t is signed)" do
      payload = event_body
      header = webhooks.generate_test_header(payload: payload, secret: secret,
                                             timestamp: Time.now.to_i - 3_600)
      expect { webhooks.construct_event(payload, header, secret) }
        .to raise_error(Nombaone::WebhookVerificationError, /tolerance/)
    end
  end

  it "is usable without an API key via Nombaone.webhooks" do
    payload = event_body(type: "invoice.paid")
    header = Nombaone.webhooks.generate_test_header(payload: payload, secret: secret)
    event = Nombaone.webhooks.construct_event(payload, header, secret)
    expect(event.type).to eq("invoice.paid")
  end

  describe Nombaone::WebhookEventType do
    it "vendors the 32-event public catalog, kept open" do
      expect(described_class::INVOICE_PAID).to eq("invoice.paid")
      expect(described_class::SUBSCRIPTION_TRIAL_WILL_END).to eq("subscription.trial_will_end")
      expect(described_class::ALL.size).to eq(32)
    end
  end
end
