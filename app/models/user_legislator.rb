# == Schema Information
#
# Table name: user_legislators
#
#  id            :bigint           not null, primary key
#  legislator_id :bigint           not null
#  user_id       :bigint           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
class UserLegislator < ApplicationRecord
  belongs_to :legislator
  belongs_to :user
end
