class AddThemePreferencesToUsers < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:users, :theme)
      add_column :users, :theme, :string, default: "neutral", null: false
    end

    unless column_exists?(:users, :theme_mode)
      add_column :users, :theme_mode, :string, default: "light", null: false
    end
  end
end
