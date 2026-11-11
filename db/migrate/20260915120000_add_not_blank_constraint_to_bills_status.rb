# frozen_string_literal: true

# @lat: [[bill-status-normalisation#Database check constraint against blank status]]
class AddNotBlankConstraintToBillsStatus < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :bills,
      "status IS NOT NULL AND length(trim(status, ' ' || char(9) || char(10) || char(13) || char(160) || char(8203) || char(12288))) > 0",
      name: "bills_status_not_blank"
  end
end
