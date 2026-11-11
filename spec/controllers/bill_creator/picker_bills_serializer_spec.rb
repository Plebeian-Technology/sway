# frozen_string_literal: true

require "rails_helper"

# @lat: [[bill-interesting-score#The bill interesting score#Picker reads]]
RSpec.describe BillCreator::PickerBillsSerializer, type: :service do
  describe ".call" do
    it "emits nil when all date inputs for a row are absent" do
      row = [
        1,
        "BILL-NO-DATES",
        "A Bill Without Date Inputs",
        nil,
        "introduced",
        "house",
        "bill",
        nil,
        nil,
        nil,
        "Ada",
        "Lovelace",
        0,
        0,
        nil
      ]
      scope = instance_double(ActiveRecord::Relation)
      allow(scope).to receive(:joins).with(:legislator).and_return(scope)
      allow(scope).to receive(:pluck).and_return([row])

      serialized = described_class.call(scope, locale: nil).first

      expect(serialized).to have_key(:latest_action_date_time_utc)
      expect(serialized[:latest_action_date_time_utc]).to be_nil
    end
  end

  describe ".interesting_score_normalized" do
    it "returns nil when signals is nil" do
      expect(described_class.interesting_score_normalized(nil, 5.0, 100.0)).to be_nil
    end

    it "includes testimony_engagement_score in normalized score calculation" do
      signals = {
        "vote_defection_score" => 0.0,
        "vote_abstention_score" => 0.0,
        "org_split_score" => 20.0,
        "testimony_engagement_score" => 30.0
      }
      fresh_timeliness = 10.0
      theoretical_max = 100.0

      # effective_raw = 0.0 + 0.0 + 20.0 + 30.0 + 10.0 = 60.0
      # normalized = 60.0 / 100.0 = 0.6
      result = described_class.interesting_score_normalized(signals, fresh_timeliness, theoretical_max)
      expect(result).to eq(0.6)
    end

    it "clamps normalized score to 1.0" do
      signals = {
        "vote_defection_score" => 40.0,
        "vote_abstention_score" => 10.0,
        "org_split_score" => 40.0,
        "testimony_engagement_score" => 50.0
      }
      fresh_timeliness = 10.0
      theoretical_max = 100.0

      result = described_class.interesting_score_normalized(signals, fresh_timeliness, theoretical_max)
      expect(result).to eq(1.0)
    end
  end
end
