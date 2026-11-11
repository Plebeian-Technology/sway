# frozen_string_literal: true

require "rails_helper"

RSpec.describe ArticleEngagementTrackerService do
  # @lat: [[partner-article-engagement#End-to-end attribution lifecycle]]
  let(:sway_locale) { create(:sway_locale) }
  let(:org) { create(:organization, sway_locale:, name: "The Baltimore Banner") }
  let(:bill) { create(:bill, sway_locale:) }
  let!(:article_bill) do
    ArticleBill.create!(
      bill:,
      organization: org,
      partner_slug: "the-banner",
      article_url: "https://thebaltimorebanner.com/community/housing-bill",
      article_title: "City Council Considers Housing Bill",
      published_at: Time.current
    )
  end

  describe ".track_click" do
    it "atomically increments clicks_count" do
      expect {
        described_class.track_click(article_bill:)
      }.to change { article_bill.reload.clicks_count }.by(1)
    end

    it "accepts an integer id as well" do
      expect {
        described_class.track_click(article_bill: article_bill.id)
      }.to change { article_bill.reload.clicks_count }.by(1)
    end

    it "returns false if article_bill is nil" do
      expect(described_class.track_click(article_bill: nil)).to be(false)
    end
  end

  describe ".track_registration" do
    it "increments registrations_count when attribution_key matches partner slug" do
      expect {
        described_class.track_registration(attribution_key: "partner:the-banner")
      }.to change { article_bill.reload.registrations_count }.by(1)
    end

    it "increments registrations_count when attribution_key contains article bill id" do
      expect {
        described_class.track_registration(attribution_key: "partner:the-banner:ab:#{article_bill.id}")
      }.to change { article_bill.reload.registrations_count }.by(1)
    end

    it "increments registrations_count when attribution_key contains url" do
      expect {
        described_class.track_registration(attribution_key: "partner:the-banner:housing-bill")
      }.to change { article_bill.reload.registrations_count }.by(1)
    end

    it "returns false if attribution_key is blank or unresolvable" do
      expect(described_class.track_registration(attribution_key: nil)).to be(false)
      expect(described_class.track_registration(attribution_key: "")).to be(false)
      expect(described_class.track_registration(attribution_key: "unknown-partner")).to be(false)
    end
  end

  describe ".track_vote" do
    it "increments votes_count and pro_votes_count for pro stances" do
      expect {
        described_class.track_vote(bill:, stance: "FOR", attribution_key: "partner:the-banner")
      }.to change { article_bill.reload.votes_count }.by(1)
        .and change { article_bill.reload.pro_votes_count }.by(1)
        .and change { article_bill.reload.con_votes_count }.by(0)
    end

    it "increments votes_count and con_votes_count for con stances" do
      expect {
        described_class.track_vote(bill:, stance: "AGAINST", attribution_key: "partner:the-banner")
      }.to change { article_bill.reload.votes_count }.by(1)
        .and change { article_bill.reload.con_votes_count }.by(1)
        .and change { article_bill.reload.pro_votes_count }.by(0)
    end

    it "handles symbol stances (:pro and :con)" do
      expect {
        described_class.track_vote(bill:, stance: :pro, attribution_key: "partner:the-banner")
      }.to change { article_bill.reload.pro_votes_count }.by(1)

      expect {
        described_class.track_vote(bill:, stance: :con, attribution_key: "partner:the-banner")
      }.to change { article_bill.reload.con_votes_count }.by(1)
    end

    it "returns false if parameters are missing" do
      expect(described_class.track_vote(bill: nil, stance: "FOR", attribution_key: "partner:the-banner")).to be(false)
      expect(described_class.track_vote(bill:, stance: nil, attribution_key: "partner:the-banner")).to be(false)
      expect(described_class.track_vote(bill:, stance: "FOR", attribution_key: nil)).to be(false)
    end
  end

  describe ".track_vote with attribution isolation" do
    context "when partner did not cover the voted bill" do
      let(:uncovered_bill) { create(:bill, sway_locale:, scheduled_release_date_utc: 5.days.from_now) }

      it "returns false and does not increment any article counters" do
        expect {
          result = described_class.track_vote(
            bill: uncovered_bill,
            stance: "FOR",
            attribution_key: "partner:the-banner"
          )
          expect(result).to be(false)
        }.not_to change { [article_bill.reload.votes_count, article_bill.reload.pro_votes_count, article_bill.reload.con_votes_count] }
      end

      it "returns false even when attribution_key includes a ref to the covered article" do
        expect {
          result = described_class.track_vote(
            bill: uncovered_bill,
            stance: "FOR",
            attribution_key: "partner:the-banner:housing-bill"
          )
          expect(result).to be(false)
        }.not_to change { [article_bill.reload.votes_count, article_bill.reload.pro_votes_count, article_bill.reload.con_votes_count] }
      end
    end

    context "when partner covered multiple bills" do
      let(:second_bill) { create(:bill, sway_locale:, scheduled_release_date_utc: 10.days.from_now) }
      let!(:second_article_bill) do
        ArticleBill.create!(
          bill: second_bill,
          organization: org,
          partner_slug: "the-banner",
          article_url: "https://thebaltimorebanner.com/transit/transit-funding",
          article_title: "City Council Approves Transit Funding",
          published_at: Time.current
        )
      end

      it "increments only the ArticleBill corresponding to the voted bill" do
        expect {
          result = described_class.track_vote(
            bill: second_bill,
            stance: "FOR",
            attribution_key: "partner:the-banner"
          )
          expect(result).to be(true)
        }.to change { second_article_bill.reload.votes_count }.by(1)
          .and change { second_article_bill.reload.pro_votes_count }.by(1)

        expect(article_bill.reload.votes_count).to eq(0)
        expect(article_bill.reload.pro_votes_count).to eq(0)
      end

      it "increments only the specific ArticleBill when ref matches that article" do
        expect {
          result = described_class.track_vote(
            bill: second_bill,
            stance: "AGAINST",
            attribution_key: "partner:the-banner:transit-funding"
          )
          expect(result).to be(true)
        }.to change { second_article_bill.reload.votes_count }.by(1)
          .and change { second_article_bill.reload.con_votes_count }.by(1)

        expect(article_bill.reload.votes_count).to eq(0)
      end
    end
  end

  describe ".resolve_article_bill SQL wildcard protection" do
    let(:uncovered_bill) { create(:bill, sway_locale:, scheduled_release_date_utc: 7.days.from_now) }

    it "sanitizes % wildcards so they do not match unrelated articles" do
      expect(
        described_class.resolve_article_bill(
          attribution_key: "partner:the-banner:%",
          bill_id: uncovered_bill.id
        )
      ).to be_nil
    end

    it "sanitizes _ wildcards so they do not match arbitrary single characters" do
      expect(
        described_class.resolve_article_bill(
          attribution_key: "partner:the-banner:housing_bill",
          bill_id: bill.id
        )
      ).to be_nil
    end

    it "successfully matches legitimate substring without wildcards" do
      expect(
        described_class.resolve_article_bill(
          attribution_key: "partner:the-banner:housing-bill",
          bill_id: bill.id
        )
      ).to eq(article_bill)
    end
  end

  describe "strict privacy invariants" do
    it "guarantees zero foreign keys or links from User or UserVote to ArticleBill" do
      expect(User.column_names).not_to include("article_bill_id")
      expect(User.column_names).not_to include("partner_slug")
      expect(UserVote.column_names).not_to include("article_bill_id")
      expect(UserVote.column_names).not_to include("partner_slug")
      expect(User.reflect_on_association(:article_bill)).to be_nil
      expect(UserVote.reflect_on_association(:article_bill)).to be_nil
    end
  end
end
