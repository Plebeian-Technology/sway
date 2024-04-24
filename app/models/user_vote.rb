# typed: strict
# == Schema Information
#
# Table name: user_votes
#
#  id         :bigint           not null, primary key
#  user_id    :bigint           not null
#  bill_id    :bigint           not null
#  support    :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class UserVote < ApplicationRecord
  belongs_to :user
  belongs_to :bill
end
