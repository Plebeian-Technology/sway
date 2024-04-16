class UserLegislator < ApplicationRecord
  belongs_to :legislator
  belongs_to :user
end
