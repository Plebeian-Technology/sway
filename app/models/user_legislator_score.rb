# typed: strict
# == Schema Information
#
# Table name: user_legislator_scores
#
#  id                         :bigint           not null, primary key
#  user_legislator_id         :bigint           not null
#  count_agreed               :integer
#  count_disagreed            :integer
#  count_no_legislator_vote   :integer
#  count_legislator_abstained :integer
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#
class UserLegislatorScore < ApplicationRecord
  belongs_to :user_legislator
end
