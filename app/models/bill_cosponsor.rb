class BillCosponsor < ApplicationRecord
  belongs_to :legislator
  belongs_to :bill
end
