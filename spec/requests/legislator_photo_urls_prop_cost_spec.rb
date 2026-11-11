# frozen_string_literal: true

require "rails_helper"

# @lat: [[legislator-photo-prefetch#Why the candidate set is narrowed before the term filter runs]]
RSpec.describe "The legislator photo prefetch prop reads only the reader's own representatives", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  # `|*, payload|` matches every other subscriber in spec/ — naming all five
  # parameters makes Steep check them against a narrower block type.
  def legislator_term_rows_read
    rows = 0
    subscription = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      rows += 1 if payload[:sql].to_s.include?("legislator_terms")
    end
    yield
    ActiveSupport::Notifications.unsubscribe(subscription)
    rows
  end

  def add_serving_strangers(count:, from:, sway_locale:)
    count.times do |index|
      district = create(:district, sway_locale: sway_locale, name: "Stranger District #{from + index}")
      legislator = create(
        :legislator,
        district: district,
        sway_locale: sway_locale,
        external_id: "stranger-#{from + index}"
      )
      create(:legislator_term, legislator: legislator, district: district)
    end
  end

  def visit_a_page_showing_no_legislators
    get terms_of_service_path
    expect(response).to have_http_status(:ok)
    expect(inertia).to render_component(Pages::TERMS)
  end

  it "holds steady as other people's representatives are added" do
    sway_locale, _user = setup

    add_serving_strangers(count: 2, from: 0, sway_locale: sway_locale)
    small = legislator_term_rows_read { visit_a_page_showing_no_legislators }
    expect(small).to be_positive, "measured no term rows, so this compares nothing"

    add_serving_strangers(count: 8, from: 2, sway_locale: sway_locale)
    large = legislator_term_rows_read { visit_a_page_showing_no_legislators }

    expect(large).to eq(small)
  end

  it "still offers the reader's own representative's stored portrait" do
    sway_locale, user = setup
    legislator = user.user_legislators.first.legislator
    legislator.photo.attach(
      io: StringIO.new("photo-bytes"),
      filename: "portrait.png",
      content_type: "image/png"
    )
    add_serving_strangers(count: 3, from: 0, sway_locale: sway_locale)

    get terms_of_service_path

    expect(inertia).to render_component(Pages::TERMS)
    urls = inertia.props[:legislator_photo_urls]
    expect(urls.size).to eq(1)
    expect(urls.first).to include(legislator.photo.blob.filename.to_s)
  end

  it "leaves out a representative with no current term" do
    _sway_locale, user = setup
    user.user_legislators.first.legislator.legislator_terms.destroy_all

    get terms_of_service_path

    expect(inertia).to render_component(Pages::TERMS)
    expect(inertia.props[:legislator_photo_urls]).to eq([])
  end
end
