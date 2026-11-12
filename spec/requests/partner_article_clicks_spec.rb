# frozen_string_literal: true

require "rails_helper"

# @lat: [[partner-article-engagement#End-to-end attribution lifecycle]]
RSpec.describe "Partner article click tracking", type: :request do
  include_context "SessionDouble"

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

  it "increments clicks_count once per session and increments again for a new session" do
    ref_param = "partner:the-banner:ab:#{article_bill.id}"

    get "/bills/#{bill.id}", params: {ref: ref_param}
    expect(response).to have_http_status(:ok)
    expect(article_bill.reload.clicks_count).to eq(1)

    get "/bills/#{bill.id}", params: {ref: ref_param}
    expect(response).to have_http_status(:ok)
    expect(article_bill.reload.clicks_count).to eq(1)

    session_hash.clear
    get "/bills/#{bill.id}", params: {ref: ref_param}
    expect(response).to have_http_status(:ok)
    expect(article_bill.reload.clicks_count).to eq(2)
  end

  it "tracks clicks when partner and ref are passed separately" do
    get "/bills/#{bill.id}", params: {partner: "the-banner", ref: "ab:#{article_bill.id}"}
    expect(response).to have_http_status(:ok)
    expect(article_bill.reload.clicks_count).to eq(1)

    get "/bills/#{bill.id}", params: {partner: "the-banner", ref: "ab:#{article_bill.id}"}
    expect(article_bill.reload.clicks_count).to eq(1)
  end

  it "does not increment clicks_count when the ref cannot be resolved" do
    expect {
      get "/bills/#{bill.id}", params: {ref: "partner:unknown-slug:ab:999999"}
    }.not_to change { article_bill.reload.clicks_count }
    expect(response).to have_http_status(:ok)
  end

  it "scopes partner clicks to the visited bill when visiting by partner param" do
    bill_a = create(:bill, sway_locale:)
    bill_b = create(:bill, sway_locale:)

    article_bill_a = ArticleBill.create!(
      bill: bill_a,
      organization: org,
      partner_slug: "the-banner",
      article_url: "https://thebaltimorebanner.com/community/bill-a",
      article_title: "Banner Bill A",
      published_at: 1.day.ago,
      created_at: 1.day.ago
    )

    article_bill_b = ArticleBill.create!(
      bill: bill_b,
      organization: org,
      partner_slug: "the-banner",
      article_url: "https://thebaltimorebanner.com/community/bill-b",
      article_title: "Banner Bill B",
      published_at: Time.current,
      created_at: Time.current
    )

    get "/bills/#{bill_a.id}", params: {partner: "the-banner"}
    expect(response).to have_http_status(:ok)
    expect(article_bill_a.reload.clicks_count).to eq(1)
    expect(article_bill_b.reload.clicks_count).to eq(0)
  end

  it "increments clicks_count on distinct article bills within the same session" do
    second_bill = create(:bill, sway_locale:)
    second_article_bill = ArticleBill.create!(
      bill: second_bill,
      organization: org,
      partner_slug: "the-banner",
      article_url: "https://thebaltimorebanner.com/community/second-bill",
      article_title: "Second Bill Coverage",
      published_at: Time.current
    )

    get "/bills/#{bill.id}", params: {ref: "partner:the-banner:ab:#{article_bill.id}"}
    expect(response).to have_http_status(:ok)
    expect(article_bill.reload.clicks_count).to eq(1)

    get "/bills/#{second_bill.id}", params: {ref: "partner:the-banner:ab:#{second_article_bill.id}"}
    expect(response).to have_http_status(:ok)
    expect(second_article_bill.reload.clicks_count).to eq(1)
    expect(article_bill.reload.clicks_count).to eq(1)
  end

  it "does not increment clicks when visiting an uncovered bill with a partner param" do
    uncovered_bill = create(:bill, sway_locale:)

    get "/bills/#{uncovered_bill.id}", params: {partner: "the-banner"}
    expect(response).to have_http_status(:ok)
    expect(article_bill.reload.clicks_count).to eq(0)
  end

  it "ignores an array bill_id alongside an attribution param" do
    get "/", params: {partner: "unknown-slug", bill_id: [bill.id.to_s]}
    expect(response).to have_http_status(:ok)
    expect(article_bill.reload.clicks_count).to eq(0)
  end

  it "ignores a hash bill_id alongside an attribution param" do
    get "/", params: {ref: "999999", bill_id: {a: bill.id.to_s}}
    expect(response).to have_http_status(:ok)
    expect(article_bill.reload.clicks_count).to eq(0)
  end
end
