# frozen_string_literal: true

class AddLegislativeSessionIdToBills < ActiveRecord::Migration[8.1]
  def change
    add_reference :bills, :legislative_session,
      null: true,
      foreign_key: {on_delete: :nullify},
      index: true
  end
end
