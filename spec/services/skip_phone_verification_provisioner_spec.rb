require "rails_helper"

RSpec.describe SkipPhoneVerificationProvisioner do
  # @lat: [[identity-and-access#The stand-in account borrows a jurisdiction's sample address]]
  around do |example|
    with_app_config(
      :dev_login,
      dev_account_full_name: "Skip+Flow+User",
      dev_account_sway_locale: "baltimore-maryland-united_states"
    ) do
      example.run
    end
  end

  # The address the Geocoder stub in spec/rails_helper.rb answers with, carried
  # by the :baltimore trait.
  let!(:baltimore) { create(:sway_locale, :baltimore) }

  describe ".call environment guard and admin hardening" do
    it "raises in a production env and provisions no user, before reading any setting" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))

      expect {
        expect { described_class.call(phone: "4105551200") }
          .to raise_error(/dev\/test-only/)
      }.not_to change(User, :count)
    end

    # @lat: [[identity-and-access#The stand-in account borrows a jurisdiction's sample address#The phone-verification shortcut does not grant admin access]]
    it "does not grant admin to the provisioned user" do
      stub_const("User::ADMIN_PHONES", ["4109999999"])
      user = described_class.call(phone: "4105551201")

      expect(user.is_sway_admin?).to be(false)
    end
  end

  describe ".call when SKIP_PHONE_VERIFICATION is enabled" do
    around do |example|
      previous = ENV["SKIP_PHONE_VERIFICATION"]
      begin
        ENV["SKIP_PHONE_VERIFICATION"] = "1"
        example.run
      ensure
        if previous.nil?
          ENV.delete("SKIP_PHONE_VERIFICATION")
        else
          ENV["SKIP_PHONE_VERIFICATION"] = previous
        end
      end
    end

    it "returns a provisioned User (truthy) without calling Twilio" do
      # WebMock raises on any real HTTP call, so if Twilio were contacted this
      # example would fail. Passing proves the provisioner skips the
      # verification call entirely.
      result = described_class.call(phone: "4105551299")

      expect(result).to be_a(User)
      expect(result).to be_truthy
    end

    it "creates a phone-verified User in pending state without representative assignments" do
      expect {
        described_class.call(phone: "4105551298")
      }.to change(User, :count).by(1)

      user = User.find_by!(phone: "4105551298")
      expect(user).to have_attributes(
        is_email_verified: true,
        is_phone_verified: true,
        is_registered_to_vote: true,
        is_registration_complete: false,
        registration_status: "pending"
      )
      expect(user.registered?).to be(false)
      expect(user.user_legislators.where(active: true)).to be_empty
      expect(user.is_email_verified).to be(true)
      expect(user.is_phone_verified).to be(true)
    end

    # @lat: [[identity-and-access#The stand-in account borrows a jurisdiction's sample address#The bypass skips SMS, not address registration]]
    it "preserves an existing registered account and heals its completion event" do
      user = create(:user, phone: "4105551290", full_name: "Real Name", email: "real@example.test")
      real_address = create(:address, street: "Real address", city: "Towson", region_code: "MD")
      UserAddress.create!(user:, address: real_address)
      representative = create(:legislator, district: create(:district, sway_locale: baltimore))
      user_legislator = create(:user_legislator, user:, legislator: representative, active: true)

      described_class.call(phone: user.phone)

      expect(user.reload).to have_attributes(
        full_name: "Real Name",
        email: "real@example.test",
        registration_status: "completed",
        is_registration_complete: true
      )
      expect(user.registered?).to be(true)
      expect(user.address).to eq(real_address)
      expect(user.user_legislators.where(active: true)).to contain_exactly(user_legislator)
    end

    # @lat: [[identity-and-access#The stand-in account borrows a jurisdiction's sample address#The bypass skips SMS, not address registration]]
    it "preserves verification flags on an already-completed registered account" do
      user = create(:user, phone: "4105551288", full_name: "Real Name", email: "real@example.test")
      representative = create(:legislator, district: create(:district, sway_locale: baltimore))
      create(:user_legislator, user:, legislator: representative, active: true)
      user.complete!
      user.update!(is_email_verified: false, is_phone_verified: false)

      expect(user).to have_attributes(
        registration_status: "completed",
        is_registration_complete: true,
        is_email_verified: false,
        is_phone_verified: false
      )

      described_class.call(phone: user.phone)

      expect(user.reload).to have_attributes(
        registration_status: "completed",
        is_registration_complete: true,
        is_email_verified: false,
        is_phone_verified: false,
        full_name: "Real Name",
        email: "real@example.test"
      )
    end

    it "creates an Address and UserAddress side effects" do
      expect {
        described_class.call(phone: "4105551297")
      }.to change(Address, :count).by(1).and(change(UserAddress, :count).by(1))
    end

    # @lat: [[identity-and-access#The stand-in account borrows a jurisdiction's sample address]]
    it "builds the Address from the named locale's sample address and its own city and region" do
      user = described_class.call(phone: "4105551294")

      # @lat: [[personal-detail-encryption#An encrypted column cannot be a lookup key]]
      address = user.address
      expect(address).to have_attributes(
        street: "100 N Holliday St",
        city: "Baltimore",
        region_code: "MD",
        postal_code: "21202"
      )
    end

    it "raises, naming the locale, when no sway locale carries that computed name" do
      with_app_config(
        :dev_login,
        dev_account_full_name: "Skip+Flow+User",
        dev_account_sway_locale: "gotham-new_jersey-united_states"
      ) do
        expect {
          described_class.call(phone: "4105551292")
        }.to raise_error(/gotham-new_jersey-united_states/)
      end
    end

    it "raises, naming the blank columns, when the named locale carries no sample address" do
      create(:sway_locale, :congress)

      with_app_config(
        :dev_login,
        dev_account_full_name: "Skip+Flow+User",
        dev_account_sway_locale: "congress-congress-united_states"
      ) do
        expect {
          described_class.call(phone: "4105551291")
        }.to raise_error(/sample_street, sample_postal_code, sample_latitude, sample_longitude/)
      end
    end

    # The postal code stays text, so a leading
    # zero survives all the way to the Address record.
    it "writes the postal code to the Address as text, with a leading zero preserved" do
      create(
        :sway_locale,
        city: "cambridge",
        state: "massachusetts",
        country: "united_states",
        sample_street: "123 Main St",
        sample_postal_code: "02139",
        sample_latitude: 42.3736,
        sample_longitude: -71.1097
      )

      with_app_config(
        :dev_login,
        dev_account_full_name: "Skip+Flow+User",
        dev_account_sway_locale: "cambridge-massachusetts-united_states"
      ) do
        user = described_class.call(phone: "4105551293")

        address = user.address
        expect(address.postal_code).to eq("02139")
        expect(address.postal_code).to be_a(String)
      end
    end

    it "is idempotent for repeat invocations with the same phone" do
      described_class.call(phone: "4105551296")

      expect {
        described_class.call(phone: "4105551296")
      }.not_to change(User, :count)
    end
  end

  describe ".call when SKIP_PHONE_VERIFICATION is NOT enabled" do
    around do |example|
      previous = ENV["SKIP_PHONE_VERIFICATION"]
      begin
        ENV.delete("SKIP_PHONE_VERIFICATION")
        example.run
      ensure
        ENV["SKIP_PHONE_VERIFICATION"] = previous unless previous.nil?
      end
    end

    it "still runs the provisioner body (this service does not gate on the setting)" do
      # SkipPhoneVerificationProvisioner does NOT check
      # skip_phone_verification itself; callers do. Once called, it always
      # provisions its default admin.
      result = described_class.call(phone: "4105551295")
      expect(result).to be_a(User)
    end
  end
end
