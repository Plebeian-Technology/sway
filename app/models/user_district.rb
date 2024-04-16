class UserDistrict < ApplicationRecord
  belongs_to :district
  belongs_to :user
end
