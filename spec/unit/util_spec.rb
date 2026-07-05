# frozen_string_literal: true

RSpec.describe Nombaone::Internal::Util do
  describe ".camelize" do
    it "leaves single words unchanged" do
      expect(described_class.camelize(:email)).to eq("email")
      expect(described_class.camelize("url")).to eq("url")
    end

    it "converts snake_case to camelCase, mirroring the wire's exact names" do
      expect(described_class.camelize(:customer_id)).to eq("customerId")
      expect(described_class.camelize(:customer_ref)).to eq("customerRef")
      expect(described_class.camelize(:plan_ref)).to eq("planRef")
      expect(described_class.camelize(:amount_in_kobo)).to eq("amountInKobo")
      expect(described_class.camelize(:unit_amount_in_kobo)).to eq("unitAmountInKobo")
    end
  end

  describe ".serialize_body" do
    it "drops omitted keys but keeps explicit nils (nullable-to-clear)" do
      body = described_class.serialize_body(
        name: "Ada", phone: nil, description: Nombaone::Internal::OMIT,
      )
      expect(body).to eq("name" => "Ada", "phone" => nil)
    end

    it "camelizes nested hash keys" do
      body = described_class.serialize_body(branding: { display_name: "Acme",
                                                        support_email: "s@a" })
      expect(body).to eq("branding" => { "displayName" => "Acme", "supportEmail" => "s@a" })
    end

    it "never rewrites the keys inside metadata or payload" do
      body = described_class.serialize_body(metadata: { crm_id: "x", "Mixed_Key" => 1 })
      expect(body).to eq("metadata" => { crm_id: "x", "Mixed_Key" => 1 })
    end

    it "keeps integer kobo values as integers" do
      body = described_class.serialize_body(amount_in_kobo: 250_000)
      expect(body["amountInKobo"]).to eq(250_000)
      expect(body["amountInKobo"]).to be_a(Integer)
    end
  end

  describe ".serialize_query" do
    it "drops omitted and nil filters, camelizes keys, stringifies values" do
      query = described_class.serialize_query(
        customer_id: "nbo1", limit: 20, active: true,
        status: nil, cursor: Nombaone::Internal::OMIT
      )
      expect(query).to eq("customerId" => "nbo1", "limit" => "20", "active" => "true")
    end
  end

  describe ".encode_path_segment" do
    it "percent-encodes like encodeURIComponent" do
      expect(described_class.encode_path_segment("nbo000000000001cus")).to eq("nbo000000000001cus")
      expect(described_class.encode_path_segment("a b/c")).to eq("a%20b%2Fc")
    end
  end

  describe ".generate_idempotency_key" do
    it "returns a fresh UUID each time" do
      a = described_class.generate_idempotency_key
      b = described_class.generate_idempotency_key
      expect(a).to match(SpecSupport::ClientHelpers::UUID_PATTERN)
      expect(a).not_to eq(b)
    end
  end

  describe ".backoff_seconds" do
    it "stays within the full-jitter envelope [0, min(8, 0.5*2^attempt))" do
      100.times do |i|
        attempt = i % 6
        cap = [8.0, 0.5 * (2**attempt)].min
        value = described_class.backoff_seconds(attempt)
        expect(value).to be >= 0
        expect(value).to be < cap
      end
    end
  end

  describe ".retry_after_seconds" do
    it "parses delta-seconds" do
      expect(described_class.retry_after_seconds("17")).to eq(17.0)
      expect(described_class.retry_after_seconds("0")).to eq(0.0)
    end

    it "returns nil when absent or unparseable" do
      expect(described_class.retry_after_seconds(nil)).to be_nil
      expect(described_class.retry_after_seconds("soon")).to be_nil
    end

    it "parses an HTTP-date into a non-negative delay" do
      future = (Time.now + 120).httpdate
      expect(described_class.retry_after_seconds(future)).to be_between(0, 121)
    end
  end

  describe ".merge_headers" do
    it "lowercases names, lets later layers win, and deletes on nil" do
      merged = described_class.merge_headers(
        { "Authorization" => "Bearer a", "Accept" => "application/json" },
        { "authorization" => "Bearer b" },
        { "accept" => nil },
      )
      expect(merged).to eq("authorization" => "Bearer b")
    end
  end
end
