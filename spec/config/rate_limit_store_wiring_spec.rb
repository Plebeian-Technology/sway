# frozen_string_literal: true

require "rails_helper"

# @lat: [[identity-and-access#Identity and access#The rate limit store swaps in after boot]]
# @lat: [[steep-typed-spec-helpers#let and def inside a describe block]]
RSpec.describe "Rate limit store wiring" do
  around do |example|
    original_backend = ApplicationController::RATE_LIMIT_STORE.instance_variable_get(:@backend)
    begin
      example.run
    ensure
      ApplicationController::RATE_LIMIT_STORE.backend = original_backend
    end
  end

  it "counts increments when wired to a real cache (the production backend = Rails.cache path)" do
    memory = ActiveSupport::Cache::MemoryStore.new
    allow(Rails).to receive(:cache).and_return(memory)

    # Do by hand what the initializer does everywhere except the test env.
    ApplicationController::RATE_LIMIT_STORE.backend = Rails.cache

    expect(ApplicationController::RATE_LIMIT_STORE.instance_variable_get(:@backend)).to equal(memory)
    # SwappableCacheStore forwards increment through method_missing, so there is no RBS signature for it;
    # the repo skips type-checking these calls.
    expect(ApplicationController::RATE_LIMIT_STORE.increment("ws1_10_probe", 1, expires_in: 60)).to eq(1) # steep:ignore
    expect(ApplicationController::RATE_LIMIT_STORE.increment("ws1_10_probe", 1, expires_in: 60)).to eq(2) # steep:ignore
  end

  it "is a silent no-op with the default NullStore backend (documents why the wiring exists)" do
    ApplicationController::RATE_LIMIT_STORE.backend = ActiveSupport::Cache::NullStore.new

    # NullStore#increment returns nil, so Rails 8's rate_limit never trips.
    # That is the exact production bug the initializer fixes.
    expect(ApplicationController::RATE_LIMIT_STORE.increment("ws1_10_probe_null", 1, expires_in: 60)).to be_nil # steep:ignore
  end

  it "ships the initializer that arms the backend outside test" do
    source = Rails.root.join("config", "initializers", "rate_limit_store.rb").read
    expect(source).to include("ApplicationController::RATE_LIMIT_STORE.backend = Rails.cache")
    expect(source).to match(/unless Rails\.env\.test\?/)
  end
end
