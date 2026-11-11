# frozen_string_literal: true

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

class ArticleBill < ApplicationRecord
  # @lat: [[partner-article-engagement#Data model and join relationship]]
  belongs_to :bill
  belongs_to :organization

  validates :partner_slug, :article_url, :article_title, presence: true
  validates :article_url, uniqueness: {scope: :bill_id}
end
