# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "sway:addresses:backfill_normalized_keys" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("sway:addresses:backfill_normalized_keys")
  end

  before { Rake::Task["sway:addresses:backfill_normalized_keys"].reenable }

  it "fills normalized_key for a geocoded row that has none yet" do
    address = create(:address)
    expect(address.normalized_key).to be_nil
    expected_key = address.computed_normalized_key

    Rake::Task["sway:addresses:backfill_normalized_keys"].invoke

    expect(address.reload.normalized_key).to eq(expected_key)
  end

  it "leaves an ungeocoded row's normalized_key nil" do
    address = create(:address)
    address.update_columns(latitude: nil, longitude: nil)

    Rake::Task["sway:addresses:backfill_normalized_keys"].invoke

    expect(address.reload.normalized_key).to be_nil
  end

  it "reports rows that end up sharing a key without changing which rows exist" do
    first = create(:address, street2: nil, street3: nil)
    second = create(:address, street2: nil, street3: nil)
    expect(first.reload.computed_normalized_key).to eq(second.reload.computed_normalized_key)

    expect { Rake::Task["sway:addresses:backfill_normalized_keys"].invoke }
      .to output(/shared by more than one row.*#{first.id}.*#{second.id}|shared by more than one row.*#{second.id}.*#{first.id}/m)
      .to_stdout

    expect(Address.count).to eq(2)
    expect(first.reload.normalized_key).to eq(second.reload.normalized_key)
  end

  it "changes no user_addresses rows" do
    user_address = create(:user_address)
    original_attributes = user_address.reload.attributes

    Rake::Task["sway:addresses:backfill_normalized_keys"].invoke

    expect(user_address.reload.attributes).to eq(original_attributes)
  end
end
