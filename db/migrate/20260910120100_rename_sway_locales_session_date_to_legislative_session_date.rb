# frozen_string_literal: true

class RenameSwayLocalesSessionDateToLegislativeSessionDate < ActiveRecord::Migration[8.1]
  def change
    rename_column :sway_locales, :current_session_start_date, :current_legislative_session_start_date
  end
end
