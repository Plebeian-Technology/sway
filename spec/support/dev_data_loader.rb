# typed: true
# frozen_string_literal: true

require "open3"

shared_context "DevDataLoader" do
  def dev_db_file_path
    Rails.root.join("storage", "development.sqlite3").to_s
  end

  def dev_data_file_path
    Rails.root.join("storage", "dev-data.sql").to_s
  end

  def dev_seed_tables
    %w[legislators sway_locales districts]
  end

  def dev_seed_load_order
    %w[sway_locales districts legislators]
  end

  def dev_seed_sql
    unless File.exist?(dev_db_file_path)
      skip "No file found at path - #{dev_db_file_path}"
    end

    command =
      "sqlite3 storage/development.sqlite3 '.dump \"#{dev_seed_tables.join("\" \"")}\"' | grep '^INSERT' > #{dev_data_file_path}"
    _, stderr, status = Open3.capture3(command)

    expect(status.success?).to be true
    expect(stderr).to be_empty

    File.read(dev_data_file_path).gsub(
      "'environment','development'",
      "'environment','test'",
    )
  end

  def reset_dev_seed_tables!
    Legislator.destroy_all
    District.destroy_all
    SwayLocale.destroy_all
  end

  def load_dev_seed_sql!(sql)
    statements_by_table = Hash.new { |hash, key| hash[key] = [] }
    remaining_statements = []

    sql.each_line do |line|
      statement = line.strip
      next if statement.empty?

      table_name = statement[/\AINSERT INTO "?([a-z_]+)"?/i, 1]

      if table_name.nil?
        remaining_statements << statement
        next
      end

      statements_by_table[table_name] << statement
    end

    ordered_statements = []
    dev_seed_load_order.each do |table_name|
      ordered_statements.concat(statements_by_table.delete(table_name) || [])
    end
    statements_by_table.each_value do |statements|
      ordered_statements.concat(statements)
    end
    ordered_statements.concat(remaining_statements)

    ordered_statements.each do |statement|
      ActiveRecord::Base.connection.execute(statement)
    end
  end
end
