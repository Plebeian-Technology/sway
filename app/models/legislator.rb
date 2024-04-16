class Legislator < ApplicationRecord
  belongs_to :address
  belongs_to :district
  
  has_one :sway_locale, through: :district

  has_many :bill
end
