# frozen_string_literal: true

RSpec.describe Nombaone::NombaObject do
  subject(:object) do
    described_class.new(
      {
        "id" => "nbo000000000001cus",
        "amountInKobo" => 250_000,
        "createdAt" => "2026-07-05T10:00:00.000Z",
        "phone" => nil,
        "metadata" => { "crm_id" => "crm_812" },
        "items" => [{ "priceId" => "nbo000000000001prc", "quantity" => 1 }],
      },
      request_id: "req_abc",
      response: nil,
    )
  end

  it "exposes snake_case readers derived from camelCase wire keys" do
    expect(object.id).to eq("nbo000000000001cus")
    expect(object.amount_in_kobo).to eq(250_000)
    expect(object.created_at).to eq("2026-07-05T10:00:00.000Z")
  end

  it "keeps money as an Integer" do
    expect(object.amount_in_kobo).to be_a(Integer)
  end

  it "reads by bracket with snake or wire names, String or Symbol" do
    expect(object[:amount_in_kobo]).to eq(250_000)
    expect(object["amountInKobo"]).to eq(250_000)
    expect(object[:missing]).to be_nil
  end

  it "wraps nested objects and arrays of objects" do
    expect(object.items.first).to be_a(described_class)
    expect(object.items.first.price_id).to eq("nbo000000000001prc")
  end

  it "keeps metadata keys verbatim (no case rewriting)" do
    expect(object.metadata.to_h).to eq("crm_id" => "crm_812")
    expect(object.metadata.crm_id).to eq("crm_812")
  end

  it "digs through nested objects and arrays" do
    expect(object.dig(:items, 0, :price_id)).to eq("nbo000000000001prc")
    expect(object.dig(:items, 5, :price_id)).to be_nil
  end

  it "distinguishes a present null field from an absent one" do
    expect(object.phone).to be_nil
    expect(object.key?(:phone)).to be(true)
    expect(object.key?(:nope)).to be(false)
  end

  it "raises NoMethodError for an unknown reader but nil for unknown bracket" do
    expect { object.definitely_not_here }.to raise_error(NoMethodError)
    expect(object[:definitely_not_here]).to be_nil
  end

  it "responds_to? known readers" do
    expect(object).to respond_to(:amount_in_kobo)
    expect(object).not_to respond_to(:definitely_not_here)
  end

  it "exposes the raw wire hash via to_h and the request id" do
    expect(object.to_h).to include("amountInKobo" => 250_000)
    expect(object.request_id).to eq("req_abc")
  end

  it "compares by underlying wire hash" do
    twin = described_class.new(object.to_h)
    expect(object).to eq(twin)
    expect(object).not_to eq(described_class.new({ "id" => "other" }))
  end
end
