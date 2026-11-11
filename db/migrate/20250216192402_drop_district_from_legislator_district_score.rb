class DropDistrictFromLegislatorDistrictScore < ActiveRecord::Migration[8.0]
  def change
    remove_column :legislator_district_scores, :district_id
  end
end
