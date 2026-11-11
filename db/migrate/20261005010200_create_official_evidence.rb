# frozen_string_literal: true

class CreateOfficialEvidence < ActiveRecord::Migration[8.1]
  def up
    create_official_evidence unless table_exists?(:official_evidence)
    validate_existing_table!
    add_index :official_evidence, [:external_record_id, :jurisdiction], name: "index_official_evidence_on_record_and_jurisdiction" unless index_exists?(:official_evidence, name: "index_official_evidence_on_record_and_jurisdiction")
    add_index :official_evidence, [:jurisdiction, :retrieved_at], name: "index_official_evidence_on_jurisdiction_and_retrieved" unless index_exists?(:official_evidence, name: "index_official_evidence_on_jurisdiction_and_retrieved")
    hash_index = indexes(:official_evidence).find { |index| index.name == "index_official_evidence_on_hash_and_source" }
    remove_index :official_evidence, name: hash_index.name if hash_index && !hash_index.unique
    add_index :official_evidence, [:payload_hash, :source_url], unique: true, name: "index_official_evidence_on_hash_and_source" unless index_exists?(:official_evidence, name: "index_official_evidence_on_hash_and_source")
    add_index :official_evidence, :sway_locale_id unless index_exists?(:official_evidence, :sway_locale_id)
    add_foreign_key :official_evidence, :sway_locales unless foreign_key_exists?(:official_evidence, :sway_locales)
  end

  def down
    drop_table :official_evidence if table_exists?(:official_evidence)
  end

  private

  def create_official_evidence
    create_table :official_evidence do |t|
      t.string :publisher, null: false
      t.string :jurisdiction, null: false
      t.references :sway_locale, foreign_key: true
      t.text :source_url, null: false
      t.string :external_record_id
      t.datetime :retrieved_at, null: false
      t.text :payload, null: false
      t.string :payload_hash, limit: 64, null: false
      t.string :fact_type, null: false
      t.string :fact_presence, null: false, default: "present"
      t.json :parsed_values, null: false, default: {}
      t.string :date_precision
      t.json :date_semantics, null: false, default: {}
      t.timestamps
    end
  end

  def validate_existing_table!
    expected = {
      "publisher" => :string,
      "jurisdiction" => :string,
      "sway_locale_id" => :integer,
      "source_url" => :text,
      "external_record_id" => :string,
      "retrieved_at" => :datetime,
      "payload" => :text,
      "payload_hash" => :string,
      "fact_type" => :string,
      "fact_presence" => :string,
      "parsed_values" => :json,
      "date_precision" => :string,
      "date_semantics" => :json,
      "created_at" => :datetime,
      "updated_at" => :datetime
    }
    actual = columns(:official_evidence).index_by(&:name)
    mismatches = expected.filter_map do |name, type|
      column = actual[name]
      next "#{name} missing" unless column
      next if column.type == type

      "#{name} must be #{type}, got #{column.type}"
    end
    raise "Incompatible official_evidence table: #{mismatches.join(", ")}" if mismatches.any?

    %w[publisher jurisdiction source_url retrieved_at payload payload_hash fact_type fact_presence parsed_values date_semantics created_at updated_at].each do |name|
      raise "Incompatible official_evidence table: #{name} must be NOT NULL" unless actual.fetch(name).null == false
    end
  end
end
