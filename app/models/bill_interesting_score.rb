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
class BillInterestingScore < ApplicationRecord
  belongs_to :bill

  serialize :signals, coder: JSON

  # @lat: [[bill-interesting-score-design#Why Bill needs dependent: :delete_all on bill_interesting_scores]]
end
