require "rails_helper"
require Rails.root.join("db", "seeds", "models", "legislator")
require Rails.root.join("db", "seeds", "models", "sway_organization")
require Rails.root.join("db", "seeds", "models", "seed_llm_bill_summarization_instruction")
require Rails.root.join("db", "seeds", "models", "seed_category")

RSpec.describe "development account in db/seeds.rb", type: :request do
  include_context "SessionDouble"

  around do |example|
    with_app_config(
      :dev_login,
      dev_account_full_name: "Sway+Admin",
      dev_account_sway_locale: "baltimore-maryland-united_states"
    ) do
      example.run
    end
  end

  def prepare_prerequisites(seat_chambers: nil)
    baltimore = create(
      :sway_locale,
      :baltimore,
      sample_street: "100 N Holliday St",
      sample_postal_code: "21202",
      sample_latitude: 39.29105,
      sample_longitude: -76.61069
    )
    organization = create(:organization, name: SeedSwayOrganization::NAME, sway_locale: baltimore)
    allow(baltimore.term_rules).to receive(:seat_chambers).and_return(seat_chambers) if seat_chambers

    allow(SeedSwayLocale).to receive(:run).and_return([baltimore])
    allow(SeedLlmBillSummarizationInstruction).to receive(:run)
    allow(SeedSwayOrganization).to receive(:run).and_return([organization])
    allow(SeedCategory).to receive(:call)

    baltimore
  end

  def with_seed_environment
    env_keys = %w[
      DEFAULT_PHONE
      DEFAULT_CITY
      DEFAULT_POSTAL_CODE
      DEFAULT_REGION_CODE
      DEFAULT_STREET
      DEFAULT_LATITUDE
      DEFAULT_LONGITUDE
    ]
    previous_env = env_keys.to_h { |key| [key, ENV[key]] }
    ENV["DEFAULT_PHONE"] = "+14105551000"
    ENV["DEFAULT_CITY"] = "Wrong City"
    ENV["DEFAULT_POSTAL_CODE"] = "00000"
    ENV["DEFAULT_REGION_CODE"] = "ZZ"
    ENV["DEFAULT_STREET"] = "Wrong Street"
    ENV["DEFAULT_LATITUDE"] = "0"
    ENV["DEFAULT_LONGITUDE"] = "0"
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))

    yield
  ensure
    env_keys.each do |key|
      if previous_env.fetch(key).nil?
        ENV.delete(key)
      else
        ENV[key] = previous_env.fetch(key)
      end
    end
    allow(Rails).to receive(:env).and_call_original
  end

  def required_admin_address(admin)
    admin.address || raise("Development admin has no address")
  end

  def active_mayor(pairings)
    pairing = pairings.find { |candidate| candidate.legislator.active_term&.title == "Mayor" }
    pairing&.legislator || raise("Development admin has no active Mayor pairing")
  end

  def required_pairing_district(pairing)
    pairing.legislator.district || raise("Active pairing has no legislator district")
  end

  # @lat: [[identity-and-access#The stand-in account borrows a jurisdiction's sample address#The primary development admin registers in Baltimore only]]
  it "registers the primary account from the sample address on repeat runs" do
    baltimore = prepare_prerequisites
    seeded_address = nil

    with_seed_environment do
      load Rails.root.join("db", "seeds.rb")

      admin = User.find_by!(phone: "4105551000")
      address = required_admin_address(admin)
      seeded_address = address
      first_counts = [Address.count, UserAddress.count, admin.user_legislators.count]

      load Rails.root.join("db", "seeds.rb")
      admin.reload
      active_pairings = admin.user_legislators.where(active: true).includes(legislator: :district).to_a
      second_counts = [Address.count, UserAddress.count, admin.user_legislators.count]

      expect(address).to have_attributes(
        street: "100 N Holliday St",
        city: "Baltimore",
        region_code: "MD",
        postal_code: "21202"
      )
      expect(address.normalized_key).to eq(
        Address.normalized_key_for(latitude: 39.29105, longitude: -76.61069)
      )
      expect(SwayGeocode.build(baltimore, address).districts).not_to be_empty
      expect(admin).to be_registered
      expect(admin.full_name).to eq("Sway Admin")
      expect(admin.registration_status).to eq("completed")
      expect(admin.is_registration_complete).to be(true)
      expect(admin.is_email_verified).to be(true)
      expect(admin.is_phone_verified).to be(true)
      expect(admin.is_registered_to_vote).to be(true)
      expect(active_pairings).not_to be_empty
      expect(active_pairings.map { |pairing| pairing.legislator.active_term&.seat&.seat_identifier }.uniq.length)
        .to eq(active_pairings.length)
      pairing_locales = active_pairings.map { |pairing| required_pairing_district(pairing).sway_locale_id }
      expect(pairing_locales.uniq)
        .to eq([baltimore.id])
      expect(active_pairings.map { |pairing| pairing.legislator.active_term&.title }).to include("Mayor")
      mayor = active_mayor(active_pairings)

      expect(mayor.active_term&.seat&.chamber).to eq("Executive")
      expect(User.where(phone: "4105551000").count).to eq(1)
      expect(UserAddress.where(user: admin).count).to eq(1)
      expect(second_counts).to eq(first_counts)

      sign_in(admin)
      get "/legislators", params: {sway_locale_id: baltimore.id}, headers: {"Accept" => "application/json"}
      expect(response).to have_http_status(:ok)
      expect(response).not_to be_redirect
      mayor_payload = response.parsed_body.fetch("legislators").find { |row| row.fetch("id") == mayor.id }
      expect(mayor_payload).to include("user_legislator_score" => nil)
      expect(mayor_payload.fetch("lifetime_score")).to include(
        "count_agreed" => 0,
        "count_disagreed" => 0
      )
    end

    provisioned_user = SkipPhoneVerificationProvisioner.call(phone: "4105551001")
    expect(provisioned_user.address).to eq(seeded_address)
  end

  it "resolves the seeded sample coordinates to Baltimore district geometry" do
    baltimore = prepare_prerequisites

    with_seed_environment do
      load Rails.root.join("db", "seeds.rb")
    end

    admin = User.find_by!(phone: "4105551000")
    address = required_admin_address(admin)

    expect(SwayGeocode.build(baltimore, address).districts).not_to be_empty
  end

  it "refuses a current roster role with missing chamber metadata before creating the admin" do
    prepare_prerequisites(seat_chambers: {"Council President" => "City Council", "Council Member" => "City Council"})
    address_count = Address.count
    user_address_count = UserAddress.count
    user_legislator_count = UserLegislator.count

    with_seed_environment do
      expect { load Rails.root.join("db", "seeds.rb") }
        .to raise_error(SeedLegislator::SeedError, /no configured chamber/i)
    end

    expect(User.find_by(phone: "4105551000")).to be_nil
    expect(Address.count).to eq(address_count)
    expect(UserAddress.count).to eq(user_address_count)
    expect(UserLegislator.count).to eq(user_legislator_count)
  end
end
