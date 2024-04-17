# == Schema Information
#
# Table name: votes
#
#  id           :bigint           not null, primary key
#  voted_on_utc :datetime
#  bill_id      :bigint           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
class Vote < ApplicationRecord
  belongs_to :bill
end
