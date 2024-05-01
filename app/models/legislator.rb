# typed: true

# == Schema Information
#
# Table name: legislators
#
#  id          :integer          not null, primary key
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
#  address_id  :integer          not null
#  district_id :integer          not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  twitter     :string
#
class Legislator < ApplicationRecord
  extend T::Sig

  # use inverse_of to specify relationship
  # https://stackoverflow.com/a/59222913/6410635
  belongs_to :district, inverse_of: :legislator
  belongs_to :address

  has_one :sway_locale, through: :district

  has_many :bill
end
