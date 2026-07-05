# frozen_string_literal: true

# Pagination — every list() works three ways.
#
#   NOMBAONE_API_KEY=nbo_sandbox_… ruby -Ilib examples/02_pagination.rb

require "nombaone"

nombaone = Nombaone.new(ENV.fetch("NOMBAONE_API_KEY"), base_url: ENV["NOMBAONE_BASE_URL"])

# 1) One page.
page = nombaone.customers.list(limit: 5)
puts "page 1: #{page.data.length} customers, has_more=#{page.has_more?}"

# 2) Manual paging.
if page.next_page?
  second = page.next_page
  puts "page 2: #{second.data.length} customers"
end

# 3) Let the SDK thread the cursors — every customer across every page.
#    (each is lazy: first(3) fetches only what it needs.)
first_three = nombaone.customers.list(limit: 2).first(3)
puts "first 3 across pages: #{first_three.map(&:email).join(', ')}"

total = 0
nombaone.customers.list(limit: 20).each { |_customer| total += 1 }
puts "walked #{total} customers in total"
