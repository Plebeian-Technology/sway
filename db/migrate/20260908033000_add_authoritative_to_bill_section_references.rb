# frozen_string_literal: true

# @lat: [[legislation-pipeline#Typographic markup and declared target resolution]]
class AddAuthoritativeToBillSectionReferences < ActiveRecord::Migration[8.1]
  class MigrationBillSectionReference < ActiveRecord::Base
    self.table_name = "bill_section_references"
  end

  def change
    add_column :bill_section_references, :authoritative, :boolean, default: false, null: false
  end
end
