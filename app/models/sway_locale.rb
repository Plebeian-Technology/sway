# == Schema Information
#
# Table name: sway_locales
#
#  id         :bigint           not null, primary key
#  city       :string
#  state      :string
#  country    :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class SwayLocale < ApplicationRecord
  has_many :bills
  has_many :districts
  has_many :legislators, through: :districts
end
