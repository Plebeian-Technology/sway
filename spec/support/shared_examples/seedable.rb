# frozen_string_literal: true

require Rails.root.join("db", "seeds", "seedable")

# @lat: [[seedable-model-shared-example#The "a seedable model" shared example]]
RSpec.shared_examples "a seedable model" do |model_class:, factory_name:, natural_key_attrs:, run_seeder:|
  describe "skip guard" do
    it "seeds a new record and stamps last_seeded_at == updated_at" do
      run_seeder.call(force: false)
      persisted = model_class.find_by(natural_key_attrs)
      expect(persisted).not_to be_nil,
        "Expected #{model_class} matching #{natural_key_attrs.inspect} to exist after run_seeder.call; none found"
      expect(persisted.last_seeded_at).to eq(persisted.updated_at)
    end

    it "skips a record whose updated_at != last_seeded_at (out-of-band edited)" do
      record = create(factory_name, **natural_key_attrs)
      record.update_columns(last_seeded_at: 1.hour.ago)
      original_updated_at = record.updated_at

      run_seeder.call(force: false)

      expect(record.reload.updated_at).to eq(original_updated_at)
    end

    it "re-seeds and re-stamps when force: true even if edited out-of-band" do
      record = create(factory_name, **natural_key_attrs)
      record.update_columns(last_seeded_at: 1.hour.ago)

      run_seeder.call(force: true)

      record.reload
      expect(record.last_seeded_at).to eq(record.updated_at)
    end
  end
end
