# frozen_string_literal: true

class RemoveCurrentLegislativeSessionStartDateFromSwayLocales < ActiveRecord::Migration[8.1]
  def change
    remove_column :sway_locales, :current_legislative_session_start_date, :date
  end
end
