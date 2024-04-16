class Bill < ApplicationRecord
  
  belongs_to :legislator
  # belongs_to :sponsor

  has_many :bill_cosponsors
end
