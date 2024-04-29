# typed: false
# == Schema Information
#
# Table name: districts
#
#  id             :integer          not null, primary key
#  name           :string
#  sway_locale_id :integer          not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
class District < ApplicationRecord
  belongs_to :sway_locale

  def get_all_no_locale
    District.find(:all, exclude: :sway_locale)
  end
end
