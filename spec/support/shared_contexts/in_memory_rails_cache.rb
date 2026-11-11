# frozen_string_literal: true

RSpec.shared_context "with in-memory Rails.cache" do
  around do |ex|
    original = Rails.cache
    begin
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      Rails.cache.clear
      ex.run
    ensure
      Rails.cache = original
    end
  end
end
