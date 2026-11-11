# frozen_string_literal: true

require "rails_helper"

# @lat: [[news-review#Administrator article review actions]]
RSpec.describe "Admin news article review", type: :system, js: true do
  let(:admin_phone) { "4105550099" }
  let(:sway_locale) { create(:sway_locale, :baltimore) }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }
  let(:bill) do
    create(
      :bill,
      sway_locale: sway_locale,
      legislator: legislator,
      extracted_text: "Section 1. City Council Housing Act."
    )
  end
  let(:sway_admin_user) do
    create(:user, :registered, phone: admin_phone)
  end
  let(:news_article) do
    create(
      :news_article,
      canonical_url: "https://thebaltimorebanner.com/community/housing-bill-123",
      title: "City Council Advances Housing Bill",
      outlet_name: "The Baltimore Banner"
    )
  end
  let!(:bill_news_article) do
    create(
      :bill_news_article,
      bill: bill,
      news_article: news_article,
      approved: false,
      match_kind: "direct"
    )
  end

  around do |example|
    previous_admin_phones = User::ADMIN_PHONES.dup
    begin
      User.send(:remove_const, :ADMIN_PHONES)
      User.const_set(:ADMIN_PHONES, [admin_phone])
      example.run
    ensure
      User.send(:remove_const, :ADMIN_PHONES)
      User.const_set(:ADMIN_PHONES, previous_admin_phones)
    end
  end

  before do
    create(:user_legislator, user: sway_admin_user, legislator: legislator)
  end

  it "approves candidate article, refreshes card row without invalid response modal, and preserves unsaved summary draft" do
    create(:bill_llm_provisioning, :with_diff_content, :completed, bill: bill)

    sign_in_as(sway_admin_user)
    navigate_to_summary_tab(bill)

    summary_textarea = find("[data-testid='textarea-llm-summary']", wait: 10)
    summary_textarea.set("Unsaved local operator draft summary that must not be wiped.")

    expect(page).to have_css("[data-testid='section-BillCreatorNewsArticles']")
    expect(page).to have_css("[data-testid='badge-unapproved-#{bill_news_article.id}']", text: "Unapproved candidate")

    approve_button = find("[data-testid='news-article-card-#{bill_news_article.id}'] button", text: "Approve for this bill")
    approve_button.click

    expect(page).to have_css("[data-testid='badge-approved-#{bill_news_article.id}']", text: "Approved", wait: 10)
    expect(page).to have_button("Withdraw approval")

    expect(page).to have_no_text("All Inertia requests must receive a valid Inertia response")
    expect(page).to have_no_css(".inertia-modal")

    expect(find("[data-testid='textarea-llm-summary']").value).to eq("Unsaved local operator draft summary that must not be wiped.")

    expect(bill_news_article.reload.approved).to be(true)
    expect(bill_news_article.review_version).to eq(1)
  end
end
