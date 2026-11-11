# frozen_string_literal: true

# == Schema Information
#
# Table name: bill_summary_revisions
# Database name: primary
#
#  id                      :integer          not null, primary key
#  llm_model               :string
#  llm_provider            :string
#  origin                  :string           not null
#  publication_role        :string           not null
#  review_state            :string           not null
#  summary_markdown        :text             not null
#  created_at              :datetime         not null
#  actor_id                :integer
#  bill_id                 :integer          not null
#  news_source_snapshot_id :integer
#  restored_from_id        :integer
#
# Indexes
#
#  index_bill_summary_revisions_on_actor_id                 (actor_id)
#  index_bill_summary_revisions_on_bill_id                  (bill_id)
#  index_bill_summary_revisions_on_bill_id_and_created_at   (bill_id,created_at)
#  index_bill_summary_revisions_on_news_source_snapshot_id  (news_source_snapshot_id)
#  index_bill_summary_revisions_on_restored_from_id         (restored_from_id)
#
# Foreign Keys
#
#  actor_id                 (actor_id => users.id)
#  bill_id                  (bill_id => bills.id)
#  news_source_snapshot_id  (news_source_snapshot_id => news_article_source_snapshots.id) ON DELETE => nullify
#  restored_from_id         (restored_from_id => bill_summary_revisions.id)
#
FactoryBot.define do
  factory :bill_summary_revision do
    bill
    summary_markdown { "This is a summary of the legislation." }
    origin { "model_generation" }
    publication_role { "published" }
    review_state { "unreviewed" }
  end
end
