# frozen_string_literal: true

RSpec.describe Nombaone::Page do
  # A client whose list endpoint is scripted with three pages.
  def three_page_client
    mock = mock_connection
    mock.page([{ "id" => "a" }, { "id" => "b" }], has_more: true, next_cursor: "cur_1", limit: 2)
    mock.page([{ "id" => "c" }, { "id" => "d" }], has_more: true, next_cursor: "cur_2", limit: 2)
    mock.page([{ "id" => "e" }], has_more: false, next_cursor: nil, limit: 2)
    [build_client(mock), mock]
  end

  it "exposes the current page's data, request id, and cursor block" do
    client, = three_page_client
    page = client.request_page(method: :get, path: "/customers", query: { status: "active" })

    expect(page.data.map(&:id)).to eq(%w[a b])
    expect(page.data.first).to be_a(Nombaone::NombaObject)
    expect(page.limit).to eq(2)
    expect(page.has_more?).to be(true)
    expect(page.next_cursor).to eq("cur_1")
    expect(page.pagination.next_cursor).to eq("cur_1")
    expect(page.request_id).to eq("req_test")
  end

  it "auto-paginates every item across all pages via each" do
    client, = three_page_client
    page = client.request_page(method: :get, path: "/customers")

    ids = []
    page.each { |item| ids.push(item.id) } # rubocop:disable Style/MapIntoArray
    expect(ids).to eq(%w[a b c d e])
  end

  it "supports the full Enumerable toolbox across pages" do
    # Each terminal Enumerable op re-walks from this page, re-fetching the
    # following pages — so give each op a fresh three-page client.
    fresh_page = -> { three_page_client.first.request_page(method: :get, path: "/customers") }

    expect(fresh_page.call.map(&:id)).to eq(%w[a b c d e])
    expect(fresh_page.call.count).to eq(5)
    expect(fresh_page.call.find { |item| item.id == "d" }.id).to eq("d")
  end

  it "returns an Enumerator when each is called without a block" do
    client, = three_page_client
    page = client.request_page(method: :get, path: "/customers")

    enum = page.each
    expect(enum).to be_a(Enumerator)
    expect(enum.first(3).map(&:id)).to eq(%w[a b c])
  end

  it "fetches lazily — first(2) does not walk past the first page" do
    client, mock = three_page_client
    page = client.request_page(method: :get, path: "/customers", query: { limit: 2 })

    expect(page.first(2).map(&:id)).to eq(%w[a b])
    expect(mock.calls.length).to eq(1) # only the initial fetch happened
  end

  it "threads the cursor while preserving the original filters" do
    client, mock = three_page_client
    page = client.request_page(method: :get, path: "/customers", query: { status: "active" })

    second = page.next_page
    expect(second.data.map(&:id)).to eq(%w[c d])
    expect(mock.calls.last.url).to eq("http://api.test/v1/customers?status=active&cursor=cur_1")
  end

  it "walks pages manually with next_page? / next_page and stops at the end" do
    client, = three_page_client
    page = client.request_page(method: :get, path: "/customers")

    collected = []
    loop do
      collected.concat(page.data.map(&:id))
      break unless page.next_page?

      page = page.next_page
    end
    expect(collected).to eq(%w[a b c d e])
    expect(page.next_page?).to be(false)
    expect { page.next_page }.to raise_error(Nombaone::Error, /No next page/)
  end

  it "iterates page-by-page with each_page" do
    client, = three_page_client
    page = client.request_page(method: :get, path: "/customers")

    sizes = []
    page.each_page { |p| sizes << p.data.length }
    expect(sizes).to eq([2, 2, 1])
  end
end
