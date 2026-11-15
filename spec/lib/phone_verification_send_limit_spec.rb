# frozen_string_literal: true

require "rails_helper"

RSpec.describe PhoneVerificationSendLimit do
  include ActiveSupport::Testing::TimeHelpers

  phone = "4105557070"
  now = Time.zone.parse("2026-11-14 12:00:00")

  # @lat: [[phone-verification-rate-limits#Why one phone gets one code a minute and ten a day#The cooldown is claimed in one atomic write]]
  it "lets one of two requests that both read an empty send list through, and gives the other the minute's wait" do
    store = ActiveSupport::Cache::MemoryStore.new
    allow(store).to receive(:read).and_call_original
    allow(store).to receive(:read).with(described_class.cache_key(phone)).and_return(nil)

    first = described_class.claim(phone:, store:, now:)
    second = described_class.claim(phone:, store:, now: now + 3.seconds)

    expect(first).to be_nil
    expect(second).to eq(57)
  end

  it "keeps the minute's wait after a release" do
    store = ActiveSupport::Cache::MemoryStore.new
    described_class.claim(phone:, store:, now:)
    described_class.release(phone:, store:, sent_at: now.to_i)

    expect(described_class.claim(phone:, store:, now: now + 10.seconds)).to eq(50)
    expect(store.read(described_class.cache_key(phone))).to eq([])
  end

  it "removes only the released send from the daily list" do
    store = ActiveSupport::Cache::MemoryStore.new
    described_class.claim(phone:, store:, now:)
    described_class.claim(phone:, store:, now: now + 2.minutes)
    described_class.release(phone:, store:, sent_at: (now + 2.minutes).to_i)

    expect(store.read(described_class.cache_key(phone))).to eq([now.to_i])
  end

  it "lets a send through and logs it when the cache store cannot write the cooldown and holds no entry" do
    store = ActiveSupport::Cache::MemoryStore.new
    allow(store).to receive(:write).and_return(false)
    allow(SwayLogging).to receive(:warn)

    expect(described_class.claim(phone:, store:, now:)).to be_nil
    expect(SwayLogging).to have_received(:warn).with("phone_verification_send_limit.cooldown_unreadable")
  end

  it "still writes the cooldown, and fails open, when the atomic write fails and the entry cannot be read back" do
    store = ActiveSupport::Cache::MemoryStore.new
    key = described_class.cache_key(phone)
    allow(store).to receive(:write).and_call_original
    allow(store).to receive(:write)
      .with(described_class.cooldown_key(key), now.to_i, expires_in: described_class::COOLDOWN, unless_exist: true)
      .and_return(false)
    allow(SwayLogging).to receive(:warn)

    expect(described_class.claim(phone:, store:, now:)).to be_nil

    expect(store.read(described_class.cooldown_key(key))).to eq(now.to_i)
    expect(described_class.claim(phone:, store:, now: now + 3.seconds)).to eq(57)
  end

  it "answers with the cooldown's remainder when the daily cap is reached and the cooldown is the longer wait" do
    store = ActiveSupport::Cache::MemoryStore.new
    key = described_class.cache_key(phone)
    oldest = now.to_i - 24.hours.to_i + 30
    middle = Array.new(8) { |i| oldest + ((i + 1) * 3600) }
    store.write(key, [oldest] + middle + [now.to_i - 10], expires_in: 24.hours)
    store.write(described_class.cooldown_key(key), now.to_i - 10, expires_in: 50.seconds)

    expect(described_class.claim(phone:, store:, now:)).to eq(50)
  end

  it "refuses for one second a request in the boundary second, while the cooldown entry is still stored" do
    store = ActiveSupport::Cache::MemoryStore.new
    sent_at = Time.zone.parse("2026-11-14 12:00:00.900")
    allow(SwayLogging).to receive(:warn)

    travel_to(sent_at, with_usec: true) do
      expect(described_class.claim(phone:, store:, now: sent_at)).to be_nil
    end
    boundary = Time.zone.parse("2026-11-14 12:01:00.500")
    travel_to(boundary, with_usec: true) do
      expect(described_class.claim(phone:, store:, now: boundary)).to eq(1)
    end
    expect(store.read(described_class.cache_key(phone))).to eq([sent_at.to_i])
    expect(SwayLogging).not_to have_received(:warn)
  end
end
