# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: bill_views
# Database name: primary
#
#  id         :integer          not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  bill_id    :integer          not null
#  user_id    :integer          not null
#
# Indexes
#
#  index_bill_views_on_bill_id              (bill_id)
#  index_bill_views_on_user_id_and_bill_id  (user_id,bill_id) UNIQUE
#
# Foreign Keys
#
#  bill_id  (bill_id => bills.id)
#  user_id  (user_id => users.id)
#
RSpec.describe BillView, type: :model do
  describe "schema" do
    it "stores only id, user_id, bill_id, and timestamps" do
      expect(described_class.column_names).to match_array(%w[id user_id bill_id created_at updated_at])
    end
  end

  describe "associations" do
    it "belongs to a user and a bill" do
      user = create(:user)
      bill = create(:bill)
      view = described_class.create!(user:, bill:)

      expect(view.user).to eq(user)
      expect(view.bill).to eq(bill)
    end

    it "is destroyed when its user is destroyed" do
      user = create(:user)
      bill = create(:bill)
      described_class.create!(user:, bill:)

      expect { user.destroy! }.to change(described_class, :count).by(-1)
    end

    it "is destroyed when its bill is destroyed" do
      user = create(:user)
      bill = create(:bill)
      described_class.create!(user:, bill:)

      expect { bill.destroy! }.to change(described_class, :count).by(-1)
    end
  end

  describe "validations" do
    it "enforces uniqueness of bill per user" do
      user = create(:user)
      bill = create(:bill)
      described_class.create!(user:, bill:)

      dup = described_class.new(user:, bill:)
      expect(dup).not_to be_valid
      expect(dup.errors[:bill_id]).to be_present
    end
  end

  describe ".record_for" do
    let(:user) { create(:user) }
    let(:bill) { create(:bill) }

    it "creates one row on first call and none on subsequent calls" do
      expect { described_class.record_for(user:, bill:) }.to change(described_class, :count).by(1)
      expect { described_class.record_for(user:, bill:) }.not_to change(described_class, :count)
    end

    it "returns nil without creating a row when user or bill is nil" do
      expect { expect(described_class.record_for(user: nil, bill:)).to be_nil }.not_to change(described_class, :count)
      expect { expect(described_class.record_for(user:, bill: nil)).to be_nil }.not_to change(described_class, :count)
    end

    it "recovers from a concurrent unique-index insert race" do
      existing = described_class.create!(user:, bill:)
      allow(described_class).to receive(:find_or_create_by!).and_raise(ActiveRecord::RecordNotUnique.new("duplicate"))

      expect(described_class.record_for(user:, bill:)).to eq(existing)
    end
  end
end
