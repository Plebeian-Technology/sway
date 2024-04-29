# typed: strict
# == Schema Information
#
# Table name: votes
#
#  id           :integer          not null, primary key
#  voted_on_utc :datetime
#  bill_id      :integer          not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
class Vote < ApplicationRecord
  belongs_to :bill
end
