# frozen_string_literal: true

require "rails_helper"

# @lat: [[news-article-evidence#Changes after publication]]
# @lat: [[query-plan-indexes#A query-cost guard measures growth, not a ceiling]]
RSpec.describe "News testimony reader query cost and freshness", type: :service do
  let(:sway_locale) { create(:sway_locale) }
  let(:bill) { create(:bill, sway_locale: sway_locale) }
  let(:admin) { create(:user, :sway_admin) }

  def count_queries
    count = 0
    subscription = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      next if /SCHEMA|TRANSACTION/.match?(payload[:name].to_s)

      count += 1
    end
    yield
    ActiveSupport::Notifications.unsubscribe(subscription)
    count
  end

  def add_published_testimony(bill:, index:, stance: "support")
    article = create(
      :news_article,
      :op_ed,
      canonical_url: "https://example.com/opinion/test-article-#{index}",
      outlet_name: "The Baltimore Sun",
      author_name: "Columnist #{index}"
    )
    text_content = "Verbatim article evidence excerpt #{index} for bill #{bill.id}."
    text_version = create(
      :news_article_text_version,
      :extracted,
      news_article: article,
      text: text_content
    )
    bna = create(
      :bill_news_article,
      :approved,
      bill: bill,
      news_article: article,
      current_text_version: text_version,
      stance: stance,
      stance_version: 1,
      review_version: 1,
      approved_by: admin
    )
    testimony = create(
      :news_article_testimony,
      :published,
      bill_news_article: bna,
      news_article_text_version: text_version,
      argument_markdown: "Strong argument #{index} based on source evidence.",
      evidence_excerpt: "Verbatim article evidence excerpt #{index}",
      citation_url: article.canonical_url,
      outlet_name: article.outlet_name,
      author_name: article.author_name,
      stance: stance,
      stance_version: bna.stance_version,
      review_version: bna.review_version,
      text_digest: text_version.digest
    )
    [bna, testimony]
  end

  describe "query count invariance across published commentaries" do
    it "executes a bounded number of database queries independent of commentary count" do
      add_published_testimony(bill: bill, index: 1)

      small_count = count_queries do
        fresh_bill = Bill.find(bill.id)
        fresh_bill.news_testimonies
      end
      expect(small_count).to be_positive, "measured zero queries, so this compares nothing"

      # Add 3 additional published commentaries (1 vs 4 commentaries)
      add_published_testimony(bill: bill, index: 2)
      add_published_testimony(bill: bill, index: 3)
      add_published_testimony(bill: bill, index: 4)

      large_count = count_queries do
        fresh_bill = Bill.find(bill.id)
        fresh_bill.news_testimonies
      end

      expect(large_count).to eq(small_count)
    end

    it "maintains bounded query count when serializing via BillResource" do
      add_published_testimony(bill: bill, index: 1)

      small_resource_count = count_queries do
        fresh_bill = Bill.find(bill.id)
        BillResource.new(fresh_bill).serializable_hash
      end
      expect(small_resource_count).to be_positive

      add_published_testimony(bill: bill, index: 2)
      add_published_testimony(bill: bill, index: 3)
      add_published_testimony(bill: bill, index: 4)

      large_resource_count = count_queries do
        fresh_bill = Bill.find(bill.id)
        BillResource.new(fresh_bill).serializable_hash
      end

      expect(large_resource_count).to eq(small_resource_count)
    end
  end

  describe "staleness and invalidation between requests" do
    it "excludes commentary on the next request when approval is withdrawn" do
      bna, testimony = add_published_testimony(bill: bill, index: 1)
      expect(Bill.find(bill.id).news_testimonies).to contain_exactly(testimony)

      bna.withdraw_approval!(by: admin)

      fresh_bill = Bill.find(bill.id)
      expect(fresh_bill.news_testimonies).to be_empty
      serialized = BillResource.new(fresh_bill).serializable_hash #: Hash[Symbol, untyped]
      expect(serialized[:news_testimonies]).to be_blank
    end

    it "excludes commentary on the next request when stance changes" do
      bna, testimony = add_published_testimony(bill: bill, index: 1, stance: "support")
      expect(Bill.find(bill.id).news_testimonies).to contain_exactly(testimony)

      bna.set_stance!("oppose", by: admin)

      fresh_bill = Bill.find(bill.id)
      expect(fresh_bill.news_testimonies).to be_empty
    end

    it "excludes commentary on the next request when current_text_version changes" do
      bna, testimony = add_published_testimony(bill: bill, index: 1)
      expect(Bill.find(bill.id).news_testimonies).to contain_exactly(testimony)

      new_tv = create(
        :news_article_text_version,
        :extracted,
        news_article: bna.news_article,
        text: "Brand new text replacing previous version."
      )
      bna.update!(current_text_version: new_tv)

      fresh_bill = Bill.find(bill.id)
      expect(fresh_bill.news_testimonies).to be_empty
    end

    it "excludes commentary on the next request when review_version increments" do
      bna, testimony = add_published_testimony(bill: bill, index: 1)
      expect(Bill.find(bill.id).news_testimonies).to contain_exactly(testimony)

      bna.update!(review_version: bna.review_version + 1)

      fresh_bill = Bill.find(bill.id)
      expect(fresh_bill.news_testimonies).to be_empty
    end

    it "selectively retains eligible commentaries while excluding invalidated ones" do
      bna1, _testimony1 = add_published_testimony(bill: bill, index: 1)
      _bna2, testimony2 = add_published_testimony(bill: bill, index: 2)

      bna1.withdraw_approval!(by: admin)

      fresh_bill = Bill.find(bill.id)
      expect(fresh_bill.news_testimonies).to contain_exactly(testimony2)
    end
  end
end
