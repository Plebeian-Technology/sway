# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: article_bills
# Database name: primary
#
#  id                  :integer          not null, primary key
#  article_title       :string           not null
#  article_url         :string           not null
#  clicks_count        :integer          default(0), not null
#  con_votes_count     :integer          default(0), not null
#  partner_slug        :string           not null
#  pro_votes_count     :integer          default(0), not null
#  published_at        :datetime
#  registrations_count :integer          default(0), not null
#  votes_count         :integer          default(0), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  bill_id             :integer          not null
#  organization_id     :integer          not null
#
# Indexes
#
#  index_article_bills_on_bill_id                           (bill_id)
#  index_article_bills_on_bill_id_and_article_url           (bill_id,article_url) UNIQUE
#  index_article_bills_on_organization_id                   (organization_id)
#  index_article_bills_on_organization_id_and_published_at  (organization_id,published_at)
#  index_article_bills_on_partner_slug_and_bill_id          (partner_slug,bill_id)
#
# Foreign Keys
#
#  bill_id          (bill_id => bills.id)
#  organization_id  (organization_id => organizations.id)
#
RSpec.describe ArticleBill, type: :model do
  # @lat: [[partner-article-engagement#Data model and join relationship]]
  let(:sway_locale) { create(:sway_locale) }
  let(:organization) { create(:organization, sway_locale:, name: "The Baltimore Banner") }
  let(:bill) { create(:bill, sway_locale:) }

  describe "validations" do
    it "is valid with valid attributes" do
      article_bill = described_class.new(
        bill:,
        organization:,
        partner_slug: "the-banner",
        article_url: "https://thebaltimorebanner.com/community/housing-bill",
        article_title: "City Council Considers Housing Bill",
        published_at: Time.current
      )
      expect(article_bill).to be_valid
    end

    it "requires bill, organization, partner_slug, article_url, and article_title" do
      article_bill = described_class.new
      expect(article_bill).not_to be_valid
      expect(article_bill.errors[:bill]).to be_present
      expect(article_bill.errors[:organization]).to be_present
      expect(article_bill.errors[:partner_slug]).to be_present
      expect(article_bill.errors[:article_url]).to be_present
      expect(article_bill.errors[:article_title]).to be_present
    end

    it "enforces uniqueness of article_url scoped to bill_id" do
      described_class.create!(
        bill:,
        organization:,
        partner_slug: "the-banner",
        article_url: "https://thebaltimorebanner.com/community/housing-bill",
        article_title: "City Council Considers Housing Bill"
      )

      duplicate = described_class.new(
        bill:,
        organization:,
        partner_slug: "the-banner",
        article_url: "https://thebaltimorebanner.com/community/housing-bill",
        article_title: "Duplicate Link Attempt"
      )
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:article_url]).to be_present
    end

    it "allows the same article_url on a different bill" do
      other_bill = create(:bill)
      described_class.create!(
        bill:,
        organization:,
        partner_slug: "the-banner",
        article_url: "https://thebaltimorebanner.com/community/omnibus-bill",
        article_title: "Council Package Covers Multiple Bills"
      )

      multi_bill = described_class.new(
        bill: other_bill,
        organization:,
        partner_slug: "the-banner",
        article_url: "https://thebaltimorebanner.com/community/omnibus-bill",
        article_title: "Council Package Covers Multiple Bills"
      )
      expect(multi_bill).to be_valid
    end
  end

  describe "associations" do
    it "belongs to bill and organization" do
      ab = described_class.create!(
        bill:,
        organization:,
        partner_slug: "the-banner",
        article_url: "https://thebaltimorebanner.com/community/housing-bill",
        article_title: "City Council Considers Housing Bill"
      )
      expect(ab.bill).to eq(bill)
      expect(ab.organization).to eq(organization)
    end

    it "is linked via bill.article_bills and bill.partner_organizations" do
      ab = described_class.create!(
        bill:,
        organization:,
        partner_slug: "the-banner",
        article_url: "https://thebaltimorebanner.com/community/housing-bill",
        article_title: "City Council Considers Housing Bill"
      )
      expect(bill.article_bills).to include(ab)
      expect(bill.partner_organizations).to include(organization)
    end

    it "is linked via organization.article_bills" do
      ab = described_class.create!(
        bill:,
        organization:,
        partner_slug: "the-banner",
        article_url: "https://thebaltimorebanner.com/community/housing-bill",
        article_title: "City Council Considers Housing Bill"
      )
      expect(organization.article_bills).to include(ab)
    end
  end
end
