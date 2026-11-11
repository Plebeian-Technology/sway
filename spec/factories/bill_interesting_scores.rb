# frozen_string_literal: true

# == Schema Information
#
# Table name: bill_interesting_scores
# Database name: primary
#
#  id               :integer          not null, primary key
#  computed_at      :datetime         not null
#  normalized_score :float            not null
#  raw_score        :float            not null
#  signals          :text             not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  bill_id          :integer          not null
#
# Indexes
#
#  index_bill_interesting_scores_on_bill_id_and_id  (bill_id,id)
#
# Foreign Keys
#
#  bill_id  (bill_id => bills.id)
#
FactoryBot.define do
  factory :bill_interesting_score do
    bill
    raw_score { 42.0 }
    normalized_score { 0.42 }
    # The full per-signal breakdown, in the agreed shape: every key is present,
    # and a signal that contributed nothing is stored as 0.0.
    signals do
      {
        "vote_defection_score" => 10.0,
        "vote_abstention_score" => 0.0,
        "org_split_score" => 20.0,
        "organization_split_score" => 20.0,
        "timeliness_score" => 10.0,
        "real_for" => 3,
        "real_against" => 2,
        "real_abstain" => 0,
        "org_for" => 2,
        "organization_for" => 2,
        "org_against" => 2,
        "organization_against" => 2
      }
    end
    computed_at { Time.current }
  end
end
