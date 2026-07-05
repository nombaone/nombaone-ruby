# frozen_string_literal: true

module Nombaone
  # One page of a list result, plus everything needed to keep going. A `Page`
  # is {Enumerable}: iterating it (`each`, `map`, `select`, `first(n)`, …)
  # walks **every item across every following page**, fetching each next page
  # lazily as you go — so `list.first(3)` stops after one page.
  #
  # For a single page, read {#data}; for page-by-page control, use {#next_page}
  # / {#next_page?} or {#each_page}.
  #
  # @example Every item, cursors handled for you
  #   nombaone.customers.list.each { |customer| puts customer.email }
  #
  # @example Just this page
  #   page = nombaone.invoices.list(status: "open", limit: 50)
  #   page.data              # => [<Invoice>, …]
  #   page.next_cursor       # => "…" or nil
  #
  # @example Manual paging
  #   page = page.next_page if page.next_page?
  class Page
    include Enumerable

    # @return [Array<NombaObject>] the items on this page.
    attr_reader :data
    # @return [String, nil] the request id of the fetch that produced this page.
    attr_reader :request_id

    # @api private
    def initialize(fetcher:, query:, result:)
      @fetcher = fetcher
      @query = query || {}
      @data = Array(result.data).map { |item| item.is_a?(Hash) ? NombaObject.new(item) : item }
      @page = result.pagination || { limit: @data.length, has_more: false, next_cursor: nil }
      @request_id = result.request_id
      @response = result.response
    end

    # The applied page size (1–100; the API default is 20).
    # @return [Integer]
    def limit = @page[:limit]

    # Whether more items exist beyond this page.
    # @return [Boolean]
    def has_more? = @page[:has_more]

    # The opaque cursor for the next page, or nil when there is none.
    # @return [String, nil]
    def next_cursor = @page[:next_cursor]

    # @return [Boolean] whether {#next_page} will return another page.
    def next_page?
      has_more? && !next_cursor.nil?
    end
    alias has_next_page? next_page?

    # The cursor block as an object: `pagination.limit`, `pagination.has_more`,
    # `pagination.next_cursor`.
    # @return [NombaObject]
    def pagination
      @pagination ||= NombaObject.new(
        { "limit" => limit, "hasMore" => has_more?, "nextCursor" => next_cursor },
      )
    end

    # Fetch the next page (same filters, next cursor).
    # @return [Page]
    # @raise [Nombaone::Error] if there is no next page — check {#next_page?}.
    def next_page
      unless next_page?
        raise Error, "No next page available — check next_page? before calling next_page."
      end

      paged_query = @query.merge(cursor: next_cursor)
      Page.new(fetcher: @fetcher, query: paged_query, result: @fetcher.call(paged_query))
    end

    # Iterate every item across this and all following pages. Without a block,
    # returns an {Enumerator} (so the whole {Enumerable} toolbox works and stays
    # lazy — `each` only fetches the next page when the current one is drained).
    #
    # @yieldparam item [NombaObject]
    # @return [Enumerator, self]
    def each(&block)
      return to_enum(:each) unless block

      page = self
      loop do
        page.data.each(&block)
        break unless page.next_page?

        page = page.next_page
      end
      self
    end
    alias auto_paging_each each

    # Iterate page-by-page (this page first), fetching each next page lazily.
    #
    # @yieldparam page [Page]
    # @return [Enumerator, self]
    def each_page
      return to_enum(:each_page) unless block_given?

      page = self
      loop do
        yield page
        break unless page.next_page?

        page = page.next_page
      end
      self
    end
  end
end
