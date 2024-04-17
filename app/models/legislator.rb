# == Schema Information
#
# Table name: legislators
#
#  id          :bigint           not null, primary key
#  external_id :string           not null
#  active      :boolean          not null
#  link        :string
#  email       :string
#  title       :string
#  first_name  :string           not null
#  last_name   :string           not null
#  phone       :string
#  fax         :string
#  party       :string           not null
#  photo_url   :string
#  address_id  :bigint           not null
#  district_id :bigint           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
class Legislator < ApplicationRecord
  belongs_to :address
  belongs_to :district
  
  has_one :sway_locale, through: :district

  has_many :bill
end
