class SwayLocale < ApplicationRecord
    has_many :bills
    has_many :districts
    has_many :legislators, through: :districts
end
