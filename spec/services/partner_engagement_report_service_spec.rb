# frozen_string_literal: true

require "rails_helper"

RSpec.describe PartnerEngagementReportService do
  # @lat: [[partner-article-engagement#Newsroom reporting and Alba serialization]]
  let(:sway_locale) { create(:sway_locale) }
  let(:org) { create(:organization, sway_locale:, name: "The Baltimore Banner") }
  let(:bill_one) { create(:bill, sway_locale:, title: "First Act", scheduled_release_date_utc: nil) }
  let(:bill_two) { create(:bill, sway_locale:, scheduled_release_date_utc: 3.days.ago, title: "Second Act") }

  describe "#call" do
    context "when partner has multiple articles" do
      before do
        ArticleBill.create!(
          bill: bill_one,
          organization: org,
          partner_slug: "the-banner",
          article_url: "https://thebaltimorebanner.com/story/1",
          article_title: "Story One",
          published_at: 2.days.ago,
          clicks_count: 100,
          registrations_count: 20,
          votes_count: 15,
          pro_votes_count: 10,
          con_votes_count: 5
        )

        ArticleBill.create!(
          bill: bill_two,
          organization: org,
          partner_slug: "the-banner",
          article_url: "https://thebaltimorebanner.com/story/2",
          article_title: "Story Two",
          published_at: 1.day.ago,
          clicks_count: 50,
          registrations_count: 10,
          votes_count: 5,
          pro_votes_count: 5,
          con_votes_count: 0
        )
      end

      # @lat: [[bill-session-archiving-tests#Bill session archive tests#Partner reporting visibility]]
      it "omits archived articles from rows and aggregate counts" do
        bill_one.update!(archived_at: Time.current)
        report = described_class.new(organization: org).call
        expect(report.articles.map(&:bill_id)).to eq([bill_two.id])
        expect(report.total_articles).to eq(1)
        expect(report.total_clicks).to eq(50)
        expect(ArticleBill.count).to eq(2)
      end

      it "calculates accurate aggregate engagement metrics" do
        report = described_class.new(organization: org).call

        expect(report.partner_slug).to eq("the-banner")
        expect(report.partner_name).to eq("The Baltimore Banner")
        expect(report.total_articles).to eq(2)
        expect(report.articles_count).to eq(2)
        expect(report.total_bills_covered).to eq(2)
        expect(report.bills_count).to eq(2)
        expect(report.total_clicks).to eq(150)
        expect(report.total_registrations).to eq(30)
        expect(report.total_votes).to eq(20)
        expect(report.pro_percentage).to eq(75.0)
        expect(report.con_percentage).to eq(25.0)
        expect(report.articles.length).to eq(2)
      end
    end

    context "k-anonymity suppression" do
      it "suppresses sentiment percentages when total_votes < 5" do
        ArticleBill.create!(
          bill: bill_one,
          organization: org,
          partner_slug: "the-banner",
          article_url: "https://thebaltimorebanner.com/story/small",
          article_title: "Small Sample Story",
          published_at: Time.current,
          clicks_count: 10,
          registrations_count: 4,
          votes_count: 4,
          pro_votes_count: 4,
          con_votes_count: 0
        )

        report = described_class.new(organization: org).call

        expect(report.total_votes).to eq(4)
        expect(report.pro_percentage).to be_nil
        expect(report.con_percentage).to be_nil
      end

      it "exposes sentiment percentages when total_votes >= 5" do
        ArticleBill.create!(
          bill: bill_one,
          organization: org,
          partner_slug: "the-banner",
          article_url: "https://thebaltimorebanner.com/story/threshold",
          article_title: "Threshold Story",
          published_at: Time.current,
          clicks_count: 20,
          registrations_count: 5,
          votes_count: 5,
          pro_votes_count: 4,
          con_votes_count: 1
        )

        report = described_class.new(organization: org).call

        expect(report.total_votes).to eq(5)
        expect(report.pro_percentage).to eq(80.0)
        expect(report.con_percentage).to eq(20.0)
      end
    end

    context "date range filtering" do
      it "filters articles by publication date window" do
        ArticleBill.create!(
          bill: bill_one,
          organization: org,
          partner_slug: "the-banner",
          article_url: "https://thebaltimorebanner.com/story/past",
          article_title: "Past Story",
          published_at: 10.days.ago,
          clicks_count: 10
        )
        ArticleBill.create!(
          bill: bill_two,
          organization: org,
          partner_slug: "the-banner",
          article_url: "https://thebaltimorebanner.com/story/recent",
          article_title: "Recent Story",
          published_at: 1.day.ago,
          clicks_count: 20
        )

        report = described_class.new(
          organization: org,
          start_date: 3.days.ago,
          end_date: Time.current
        ).call

        expect(report.total_articles).to eq(1)
        expect(report.total_clicks).to eq(20)
        expect(report.articles.first.article_title).to eq("Recent Story")
      end
    end
  end
end
