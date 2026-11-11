# frozen_string_literal: true

# @lat: [[migrations-name-no-model#Migrations name no model#A column nothing writes is dropped in its own change]]
class RemoveAttachmentNameFromTestimonyAttachmentClassifications < ActiveRecord::Migration[8.1]
  def change
    remove_column :testimony_attachment_classifications, :attachment_name, :string
  end
end
