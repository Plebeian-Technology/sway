# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "seeds", "models", "sway_locale")
require Rails.root.join("db", "seeds", "models", "legislator")

RSpec.describe "President link after a Congress seed" do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Date.new(2026, 11, 14)) { example.run } }

  let(:congress) { SwayLocale.resolve_by_computed_name("congress-congress-united_states") || raise("Congress not seeded") }
  let(:president) { congress.legislators.find_by!(external_id: "POTUS") }
  let(:us0) { District.find_by!(sway_locale: congress, name: "US0") }
  let(:address) do
    create(:address, street: "400 Washington Ave", city: "Towson", region_code: "MD", postal_code: "21204", latitude: "39.4015", longitude: "-76.6019")
  end

  before do
    SeedSwayLocale.run
    SeedLegislator.run([congress])
    stub_census_district("02")
    clear_enqueued_jobs
  end

  def stub_census_district(number)
    stub_request(:get, %r{tigerweb\.geo\.census\.gov/arcgis/rest/services/TIGERweb/})
      .to_return(status: 200, body: {features: [{attributes: {"CD#{Census::CURRENT_CONGRESS_NUMBER}" => number}}]}.to_json)
  end

  def stub_census_outage
    stub_request(:get, %r{tigerweb\.geo\.census\.gov/arcgis/rest/services/TIGERweb/}).to_return(status: 503)
  end

  def register_user_before_the_president_existed
    user = create(:user)
    create(:user_address, user:, address:)
    SwayRegistrationService.new(user, address, congress, invited_by_id: nil).create_user_legislators
    UserLegislator.where(user:, legislator: president).destroy_all
    UserDistrict.where(user:, district: us0).destroy_all
    user
  end

  def reseed_congress
    perform_enqueued_jobs(only: ReconcileUserDistrictsJob) { SeedLegislator.run([congress]) }
  end

  def president_links(user)
    UserLegislator.where(user:, legislator: president)
  end

  def expect_active_president_link_and_district(user)
    expect(president_links(user).pluck(:active)).to eq([true])
    expect(UserDistrict.where(user:, district: us0).pluck(:active)).to eq([true])
  end

  # @lat: [[representative-resolution-tests#President link after a Congress seed#Links a registered user to the President]]
  it "links a registered user with an address to the President after the seed" do
    user = register_user_before_the_president_existed

    reseed_congress

    expect_active_president_link_and_district(user)
  end

  # @lat: [[representative-resolution-tests#President link after a Congress seed#Reactivates an inactive President link]]
  it "reactivates a user whose only President link was inactive" do
    user = register_user_before_the_president_existed
    create(:user_legislator, user:, legislator: president, active: false)
    create(:user_district, user:, district: us0, active: false)

    reseed_congress

    expect_active_president_link_and_district(user)
  end

  # @lat: [[representative-resolution-tests#President link after a Congress seed#Leaves one President link per user]]
  it "leaves exactly one President link per user after two seeds" do
    user = register_user_before_the_president_existed

    2.times { reseed_congress }

    expect_active_president_link_and_district(user)
    expect(UserLegislator.where(user:).group(:legislator_id).count.values.uniq).to eq([1])
  end

  # @lat: [[representative-resolution-tests#President link after a Congress seed#Retries a skipped Congress lookup]]
  it "records Congress as pending after a skipped lookup, and the hourly job then links the President" do
    user = register_user_before_the_president_existed
    stub_census_outage

    reseed_congress

    expect(president_links(user)).to be_empty
    expect(user.reload.pending_representative_locale_ids).to eq([congress.id])

    stub_census_district("02")
    AssignPendingRepresentativesJob.perform_now

    expect_active_president_link_and_district(user)
    expect(user.reload.pending_representative_locale_ids).to be_empty
  end

  # @lat: [[representative-resolution-tests#President link after a Congress seed#Links the President without a notice]]
  it "links the President without a reassignment notice" do
    user = register_user_before_the_president_existed

    expect { reseed_congress }.not_to change(RepresentativeReassignment, :count)

    expect_active_president_link_and_district(user)
    expect(enqueued_jobs.pluck("job_class")).not_to include("DeliverReassignmentNotificationJob")
  end

  # @lat: [[representative-resolution-tests#President link after a Congress seed#Still notifies for another new legislator]]
  it "still notifies for another new legislator linked in the same run" do
    user = register_user_before_the_president_existed
    senator = UserLegislator.where(user:).map(&:legislator).find { |legislator| legislator.active_term&.title == "Sen." }
    UserLegislator.where(user:, legislator: senator).destroy_all

    reseed_congress

    expect_active_president_link_and_district(user)
    expect(RepresentativeReassignment.where(user:).pluck(:legislator_id)).to eq([senator.id])
    expect(enqueued_jobs.pluck("job_class")).to include("DeliverReassignmentNotificationJob")
  end
end
