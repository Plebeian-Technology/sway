# frozen_string_literal: true

# == Schema Information
#
# Table name: law_sections
# Database name: primary
#
#  id             :integer          not null, primary key
#  article        :string           not null
#  body           :text             not null
#  key            :string           not null
#  section        :string           not null
#  source_path    :string           not null
#  title          :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  sway_locale_id :integer          not null
#
# Indexes
#
#  idx_law_sections_on_locale_key        (sway_locale_id,key) UNIQUE
#  index_law_sections_on_sway_locale_id  (sway_locale_id)
#
# Foreign Keys
#
#  sway_locale_id  (sway_locale_id => sway_locales.id)
#
require "rails_helper"

RSpec.describe LawSection, type: :model do
  describe "validations" do
    it "is valid with all required attributes" do
      expect(build(:law_section)).to be_valid
    end

    it "requires key" do
      record = build(:law_section, key: nil)
      expect(record).not_to be_valid
      expect(record.errors[:key]).to be_present
    end

    it "requires article" do
      record = build(:law_section, article: nil)
      expect(record).not_to be_valid
      expect(record.errors[:article]).to be_present
    end

    it "requires section" do
      record = build(:law_section, section: nil)
      expect(record).not_to be_valid
      expect(record.errors[:section]).to be_present
    end

    it "requires body" do
      record = build(:law_section, body: nil)
      expect(record).not_to be_valid
      expect(record.errors[:body]).to be_present
    end

    it "requires source_path" do
      record = build(:law_section, source_path: nil)
      expect(record).not_to be_valid
      expect(record.errors[:source_path]).to be_present
    end

    it "enforces key uniqueness scoped to sway_locale_id" do
      sway_locale = create(:sway_locale)
      create(:law_section, sway_locale: sway_locale, key: "art_1__sec_1")
      dup = build(:law_section, sway_locale: sway_locale, key: "art_1__sec_1")
      expect(dup).not_to be_valid
      expect(dup.errors[:key]).to be_present
    end

    it "allows the same key across different sway_locales" do
      locale_a = create(:sway_locale)
      locale_b = create(:sway_locale)
      create(:law_section, sway_locale: locale_a, key: "art_1__sec_1")
      expect(build(:law_section, sway_locale: locale_b, key: "art_1__sec_1")).to be_valid
    end
  end

  describe "associations" do
    it "belongs to sway_locale" do
      expect(LawSection.reflect_on_association(:sway_locale).macro).to eq(:belongs_to)
    end
  end

  describe ".by_sway_locale" do
    it "returns only rows belonging to the given locale" do
      locale_a = create(:sway_locale)
      locale_b = create(:sway_locale)
      a1 = create(:law_section, sway_locale: locale_a, key: "art_1__sec_1")
      _b1 = create(:law_section, sway_locale: locale_b, key: "art_1__sec_1")
      result = LawSection.by_sway_locale(locale_a)
      expect(result).to contain_exactly(a1)
    end
  end
end
