# == Schema Information
#
# Table name: bill_scores
#
#  id         :bigint           not null, primary key
#  bill_id    :bigint           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class BillScore < ApplicationRecord
  belongs_to :bill
end
