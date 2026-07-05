# frozen_string_literal: true

require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec) do |t|
  # Unit + conformance by default; the integration suite is opt-in (env-gated).
  t.pattern = "spec/{unit,conformance}/**/*_spec.rb"
end

RSpec::Core::RakeTask.new("spec:integration") do |t|
  t.pattern = "spec/integration/**/*_spec.rb"
end

RuboCop::RakeTask.new(:rubocop)

desc "Type-check the RBS signatures against the library"
task :rbs do
  sh "rbs -I sig validate"
end

task default: %i[rubocop rbs spec]
