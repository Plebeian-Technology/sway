class UserVote < ApplicationRecord
  belongs_to :user
  belongs_to :bill
end
