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
#
class Legislator < ApplicationRecord
  extend T::Sig

  belongs_to :address
  belongs_to :district

  has_one :sway_locale, through: :district

  has_many :bill

  sig { returns(T.nilable(District)) }
  attr_reader :district
end
