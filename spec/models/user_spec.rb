# == Schema Information
#
# Table name: users
# Database name: primary
#
#  id                                      :integer          not null, primary key
#  current_sign_in_at                      :datetime
#  current_sign_in_ip                      :string
#  email                                   :string
#  full_name                               :string
#  is_email_verified                       :boolean
#  is_phone_verified                       :boolean
#  is_registered_to_vote                   :boolean
#  is_registration_complete                :boolean
#  is_voter_registration_address_confirmed :boolean          default(FALSE), not null
#  last_sign_in_at                         :datetime
#  last_sign_in_ip                         :string
#  notify_on_new_position_default          :boolean          default(TRUE), not null
#  notify_on_summary_change_default        :boolean          default(TRUE), not null
#  notify_on_support_change_default        :boolean          default(TRUE), not null
#  org_position_cadence_default            :integer          default("every_change"), not null
#  phone                                   :string
#  registration_status                     :string           default("pending")
#  sign_in_count                           :integer          default(0), not null
#  sms_notifications_enabled               :boolean          default(FALSE)
#  theme                                   :string           default("neutral"), not null
#  theme_mode                              :string           default("light"), not null
#  created_at                              :datetime         not null
#  updated_at                              :datetime         not null
#  webauthn_id                             :string
#
# Indexes
#
#  index_users_on_email        (email) UNIQUE
#  index_users_on_phone        (phone) UNIQUE
#  index_users_on_webauthn_id  (webauthn_id) UNIQUE
#
require "rails_helper"

RSpec.describe User, type: :model do
  describe "#registered?" do
    it "returns true when the user has an active legislator pairing despite stale completion fields" do
      user = create(:user, is_registration_complete: false)
      create(:user_legislator, user: user)

      expect(user.registered?).to be(true)
    end

    it "returns false when the user has no legislator pairings despite completed fields" do
      user = create(:user)
      user.update_columns(is_registration_complete: true, registration_status: "completed")
      expect(user.is_registration_complete).to be(true)
      expect(user.completed?).to be(true)

      expect(user.registered?).to be(false)
      expect(user.to_sway_json.with_indifferent_access[:is_registration_complete]).to be(false)
    end

    it "serializes true when an active pairing exists despite stale false fields" do
      user = create(:user)
      create(:user_legislator, user: user)

      expect(user.to_sway_json.with_indifferent_access[:is_registration_complete]).to be(true)
    end

    it "returns false when every legislator pairing is inactive" do
      user = create(:user, is_registration_complete: true)
      pairing = create(:user_legislator, user: user)
      pairing.update!(active: false)

      expect(user.registered?).to be(false)
      expect(user.complete).to be(false)
      expect(user.reload.registration_status).to eq("pending")
      expect(user.is_registration_complete).to be(false)
    end
  end

  describe "registration completion" do
    it "does not complete or set the compatibility cache without an active pairing" do
      user = create(:user, is_registration_complete: false)

      expect(user.complete).to be(false)
      expect(user.reload.registration_status).to eq("pending")
      expect(user.is_registration_complete).to be(false)
    end
  end

  # @lat: [[identity-and-access#Registration is asynchronous by necessity]]
  describe "#complete! from a failed registration" do
    it "transitions failed -> completed and marks registration complete" do
      user = create(:user)
      create(:user_legislator, user: user)
      user.update_column(:registration_status, "failed")

      user.complete!

      expect(user.registration_status).to eq("completed")
      expect(user.is_registration_complete).to be(true)
    end

    it "heals a completed registration whose compatibility cache is false" do
      user = create(:user)
      create(:user_legislator, user: user)
      user.update_columns(registration_status: "completed", is_registration_complete: false)

      user.complete!

      expect(user.reload.registration_status).to eq("completed")
      expect(user.is_registration_complete).to be(true)
    end
  end

  # @lat: [[identity-and-access#User JSON exposes only selected fields#Invite links are created with the account]]
  describe "create_user_invite_url callback" do
    it "runs on CREATE but not on a subsequent UPDATE" do
      user = build(:user)
      allow(user).to receive(:create_user_invite_url).and_call_original

      user.save!
      expect(user).to have_received(:create_user_invite_url).once

      user.update!(full_name: "Updated Name")
      expect(user).to have_received(:create_user_invite_url).once
    end
  end

  describe "#has_sway_passkey?" do
    it "returns false when the user has no passkeys" do
      user = create(:user)

      expect(user.has_sway_passkey?).to be(false)
    end

    it "returns true when the user has at least one passkey" do
      user = create(:user)
      create(:passkey, user: user)

      expect(user.has_sway_passkey?).to be(true)
    end
  end

  describe "webauthn_id initialization" do
    it "assigns a generated webauthn_id on new records" do
      allow(WebAuthn).to receive(:generate_user_id).and_return(
        "generated-webauthn-id"
      )

      user = User.new(phone: "4105557788")

      expect(user.webauthn_id).to eq("generated-webauthn-id")
    end

    it "preserves an explicitly provided webauthn_id" do
      allow(WebAuthn).to receive(:generate_user_id)

      user = User.new(phone: "4105557789", webauthn_id: "existing-id")

      expect(user.webauthn_id).to eq("existing-id")
      expect(WebAuthn).not_to have_received(:generate_user_id)
    end

    it "keeps persisted webauthn_id unchanged on reload" do
      user = User.create!(phone: "4105557790", webauthn_id: "persisted-id")

      expect(user.reload.webauthn_id).to eq("persisted-id")
    end

    it "enforces unique webauthn_id values at the database level" do
      User.create!(phone: "4105557791", webauthn_id: "duplicate-webauthn-id")

      expect do
        User.create!(phone: "4105557792", webauthn_id: "duplicate-webauthn-id")
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  # as_json must never dump the raw database columns. It hands off to the to_builder
  # allow-list, so a User serialized by accident can still only give out vetted fields.
  describe "#as_json whitelist" do
    let(:user) { create(:user) }

    it "never includes raw sensitive attributes" do
      keys = user.as_json.keys.map(&:to_s)
      %w[current_sign_in_ip last_sign_in_ip webauthn_id sign_in_count password_digest].each do |sensitive|
        expect(keys).not_to include(sensitive)
      end
    end

    it "omits is_admin for a non-admin and emits the derived key for an admin" do
      allow(user).to receive(:is_sway_admin?).and_return(false)
      expect(user.as_json.keys.map(&:to_s)).not_to include("is_admin")

      allow(user).to receive(:is_sway_admin?).and_return(true)
      expect(user.as_json["is_admin"]).to be(true)
    end
  end

  # ADMIN_PHONES and API_USER_PHONES are built once, at class load, so a spec
  # cannot vary ENV and see the constants move. These examples call the build
  # method directly instead, the way with_env normally
  # varies a value under test.
  describe ".phone_list_from_credential (build behind ADMIN_PHONES / API_USER_PHONES)" do
    it "keeps a leading zero on the second phone number" do
      with_env("ADMIN_PHONES" => "4105551234,0105551234") do
        expect(User.send(:phone_list_from_credential, "ADMIN_PHONES"))
          .to eq(["4105551234", "0105551234"])
      end
    end

    it "drops a trailing newline kamal env push leaves, keeping only digits" do
      with_env("ADMIN_PHONES" => "4105551234,4105555678\n") do
        expect(User.send(:phone_list_from_credential, "ADMIN_PHONES"))
          .to eq(["4105551234", "4105555678"])
      end
    end

    it "returns an empty list, not a list holding one empty entry, when unset" do
      with_env("ADMIN_PHONES" => nil) do
        expect(User.send(:phone_list_from_credential, "ADMIN_PHONES")).to eq([])
      end
    end

    it "returns an empty list, not a list holding one empty entry, when blank" do
      with_env("ADMIN_PHONES" => "   ") do
        expect(User.send(:phone_list_from_credential, "ADMIN_PHONES")).to eq([])
      end
    end

    it "freezes the returned array" do
      with_env("ADMIN_PHONES" => "4105551234") do
        expect(User.send(:phone_list_from_credential, "ADMIN_PHONES")).to be_frozen
      end
    end
  end

  # @lat: [[seeded-development-users#Factory users draw from the same unroutable range]]
  describe "the :user factory's phone numbers" do
    it "mints distinct numbers in the unassigned 333 area code" do
      phones = create_list(:user, 3).map(&:phone)

      expect(phones.uniq.length).to eq(3)
      expect(phones).to all(match(/\A333\d{7}\z/))
    end
  end

  describe "ADMIN_PHONES and API_USER_PHONES" do
    it "are frozen arrays" do
      expect(User::ADMIN_PHONES).to be_frozen
      expect(User::API_USER_PHONES).to be_frozen
    end
  end

  # @lat: [[personal-detail-encryption#What is encrypted on a user]]
  describe "encrypted personal details" do
    let(:raw_column) do
      lambda do |user, column|
        ActiveRecord::Base.connection.select_value("SELECT #{column} FROM users WHERE id = #{user.id}")
      end
    end

    it "stores the name and both sign-in addresses as ciphertext" do
      user = create(:user, full_name: "Ada Lovelace", current_sign_in_ip: "203.0.113.7",
        last_sign_in_ip: "198.51.100.4")

      expect(raw_column.call(user, "full_name")).not_to eq("Ada Lovelace")
      expect(raw_column.call(user, "current_sign_in_ip")).not_to eq("203.0.113.7")
      expect(raw_column.call(user, "last_sign_in_ip")).not_to eq("198.51.100.4")
    end

    it "still shows a person their own name" do
      user = create(:user, full_name: "Ada Lovelace")

      expect(User.find(user.id).full_name).to eq("Ada Lovelace")
    end

    it "still records the address a sign-in came from" do
      user = create(:user)
      user.update!(last_sign_in_ip: user.current_sign_in_ip, current_sign_in_ip: "203.0.113.9")

      expect(User.find(user.id).current_sign_in_ip).to eq("203.0.113.9")
    end

    it "gives one value different ciphertext each time, so rows cannot be grouped" do
      first = create(:user, full_name: "Ada Lovelace")
      second = create(:user, full_name: "Ada Lovelace")

      expect(raw_column.call(first, "full_name")).not_to eq(raw_column.call(second, "full_name"))
    end

    it "still reads a row the conversion has not reached" do
      user = create(:user, full_name: "Ada Lovelace")
      ActiveRecord::Base.connection.execute(
        "UPDATE users SET full_name = 'Grace Hopper' WHERE id = #{user.id}"
      )

      expect(User.find(user.id).full_name).to eq("Grace Hopper")
    end
  end

  # @lat: [[personal-detail-encryption#Why the mode is not a free choice]]
  describe "encrypted email" do
    def raw_email(user)
      ActiveRecord::Base.connection.select_value("SELECT email FROM users WHERE id = #{user.id}")
    end

    it "stores the address as ciphertext" do
      user = create(:user, email: "ada@example.com")

      expect(raw_email(user)).not_to eq("ada@example.com")
    end

    it "reads the address back" do
      user = create(:user, email: "ada@example.com")

      expect(User.find(user.id).email).to eq("ada@example.com")
    end

    it "gives one address the same ciphertext every time, so the unique rule still compares" do
      first = create(:user, email: "ada@example.com")
      first_ciphertext = raw_email(first)
      first.update!(email: "other@example.com")
      first.update!(email: "ada@example.com")

      expect(raw_email(first)).to eq(first_ciphertext)
    end

    it "still refuses a second account with the same address" do
      create(:user, email: "ada@example.com")
      duplicate = build(:user, email: "ada@example.com")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:email]).to be_present
    end

    it "still refuses a duplicate of an address a conversion has not reached" do
      existing = create(:user, email: "ada@example.com")
      ActiveRecord::Base.connection.execute(
        "UPDATE users SET email = 'grace@example.com' WHERE id = #{existing.id}"
      )
      duplicate = build(:user, email: "grace@example.com")

      expect(duplicate).not_to be_valid
    end
  end

  # @lat: [[personal-detail-encryption#Why the phone number takes the weaker mode]]
  describe "encrypted phone" do
    def raw_phone(user)
      ActiveRecord::Base.connection.select_value("SELECT phone FROM users WHERE id = #{user.id}")
    end

    it "stores the number as ciphertext" do
      user = create(:user, phone: "4105550456")

      expect(raw_phone(user)).not_to eq("4105550456")
    end

    it "still finds the account by its number, which is how every sign-in works" do
      user = create(:user, phone: "4105550456")

      expect(User.find_by(phone: "4105550456")&.id).to eq(user.id)
    end

    it "still refuses a second account with the same number" do
      create(:user, phone: "4105550456")
      duplicate = build(:user, phone: "4105550456")

      expect(duplicate).not_to be_valid
    end

    it "still finds an account the conversion has not reached" do
      user = create(:user, phone: "4105550456")
      ActiveRecord::Base.connection.execute(
        "UPDATE users SET phone = '4105550999' WHERE id = #{user.id}"
      )

      expect(User.find_by(phone: "4105550999")&.id).to eq(user.id)
    end

    it "still refuses a duplicate of a number the conversion has not reached" do
      user = create(:user, phone: "4105550456")
      ActiveRecord::Base.connection.execute(
        "UPDATE users SET phone = '4105550999' WHERE id = #{user.id}"
      )
      duplicate = build(:user, phone: "4105550999")

      expect(duplicate).not_to be_valid
    end
  end

  describe "#record_funnel_event registration tracking" do
    let(:user) { create(:user) }
    let(:sway_locale) { create(:sway_locale) }
    let(:org) { create(:organization, sway_locale:, name: "The Baltimore Banner") }
    let(:bill) { create(:bill, sway_locale:) }
    let!(:article_bill) do
      ArticleBill.create!(
        bill:,
        organization: org,
        partner_slug: "the-banner",
        article_url: "https://thebaltimorebanner.com/housing",
        article_title: "Housing",
        published_at: Time.current
      )
    end

    it "tracks registration on first geocoding_completed and deduplicates on replay" do
      user.registration_funnel_events.create!(
        visitor_token: "vis-123",
        attribution_key: "partner:the-banner",
        step: :landing,
        metadata: {}
      )

      expect {
        user.record_funnel_event(:geocoding_completed)
      }.to change { article_bill.reload.registrations_count }.by(1)

      expect {
        user.record_funnel_event(:geocoding_completed)
      }.not_to change { article_bill.reload.registrations_count }
    end
  end

  # @lat: [[admin-hub-index#Who sees the monitoring link]]
  describe "#monitoring_admin? and #beszel_url" do
    around do |example|
      with_app_config(:ops, beszel_admin_email_domains: ["ops.example.org"]) { example.run }
    end

    it "returns the Beszel URL and includes it in JSON only for a sway admin on a listed email domain" do
      admin = create(:user, :sway_admin)
      admin.update!(email: "Operator@OPS.example.org")

      expect(admin.monitoring_admin?).to be(true)
      expect(admin.beszel_url).to eq("http://sway-test.invalid:8090")
      expect(admin.to_sway_json.with_indifferent_access[:beszel_url]).to eq("http://sway-test.invalid:8090")
    end

    it "omits beszel_url for a sway admin whose email is not on a listed domain" do
      admin = create(:user, :sway_admin)
      admin.update!(email: "operator@example.com")

      expect(admin.monitoring_admin?).to be(false)
      expect(admin.beszel_url).to be_nil
      expect(admin.to_sway_json.with_indifferent_access).not_to have_key(:beszel_url)
    end

    it "does not treat a listed domain as a suffix of a longer one" do
      admin = create(:user, :sway_admin)
      admin.update!(email: "operator@notops.example.org")

      expect(admin.monitoring_admin?).to be(false)
    end

    it "omits beszel_url for every sway admin when no domain is configured" do
      admin = create(:user, :sway_admin)
      admin.update!(email: "operator@ops.example.org")

      with_app_config(:ops, beszel_admin_email_domains: []) do
        expect(admin.monitoring_admin?).to be(false)
        expect(admin.beszel_url).to be_nil
      end
    end

    it "omits beszel_url for a non-admin even when their email is on a listed domain" do
      reader = create(:user)
      reader.update!(email: "reader@ops.example.org")
      User.send(:remove_const, :ADMIN_PHONES)
      User.const_set(:ADMIN_PHONES, ["+10000000000"])

      expect(reader.monitoring_admin?).to be(false)
      expect(reader.beszel_url).to be_nil
      expect(reader.to_sway_json.with_indifferent_access).not_to have_key(:beszel_url)
    end
  end

  describe "#default_sway_locale" do
    let(:user) { create(:user) }

    it "resolves to maryland when sway_locales are bethesda (undeclared), maryland (declared), congress (declared)" do
      bethesda = create(:sway_locale, city: "bethesda", state: "MD", country: "United States")
      maryland = create(:sway_locale, :maryland)
      congress = create(:sway_locale, :congress)
      allow(user).to receive(:sway_locales).and_return([bethesda, maryland, congress])

      expect(user.default_sway_locale).to eq(maryland)
    end

    it "resolves to congress when sway_locales are austin (undeclared), texas (undeclared), congress (declared)" do
      austin = create(:sway_locale, city: "austin", state: "texas", country: "united_states")
      texas = create(:sway_locale, city: "texas", state: "texas", country: "united_states")
      congress = create(:sway_locale, :congress)
      allow(user).to receive(:sway_locales).and_return([austin, texas, congress])

      expect(user.default_sway_locale).to eq(congress)
    end

    it "falls back to the non-Congress locale first when all locales are undeclared" do
      undeclared_city = create(:sway_locale, city: "bethesda", state: "MD", country: "United States")
      undeclared_state = create(:sway_locale, city: "texas", state: "texas", country: "united_states")
      undeclared_congress = create(:sway_locale, city: "congress", state: "congress", country: "canada")
      allow(user).to receive(:sway_locales).and_return([undeclared_city, undeclared_state, undeclared_congress])

      expect(user.default_sway_locale).to eq(undeclared_city)
    end

    it "returns nil when sway_locales is empty" do
      allow(user).to receive(:sway_locales).and_return([])

      expect(user.default_sway_locale).to be_nil
    end
  end

  describe "account deletion foreign-key guard" do
    it "fails when a foreign key to users is neither handled nor allowlisted" do
      admin_actor_foreign_keys = [
        ["admin_bill_views", "admin_user_id"],
        ["admin_settings", "updated_by_id"],
        ["bill_news_articles", "approved_by_id"],
        ["bill_news_articles", "stance_by_id"],
        ["bill_summary_revisions", "actor_id"],
        ["historical_repair_audit_events", "admin_user_id"],
        ["news_article_discovery_requests", "requested_by_id"],
        ["news_article_source_snapshots", "actor_id"],
        ["news_article_text_versions", "actor_id"],
        ["pipeline_activity_log_entries", "actor_user_id"],
        ["sending_service_domains", "confirmed_by_id"],
        ["testimony_coverage_acknowledgements", "acknowledged_by_id"]
      ].freeze

      allowed_nullify_keys = [
        ["bill_summary_reports", "resolved_by_id"]
      ].freeze

      allowed_nullify_associations = %i[
        resolved_bill_summary_reports
        approved_position_changes
        rejected_position_changes
      ].freeze

      pending_foreign_keys = [].freeze

      conn = ActiveRecord::Base.connection
      user_fks = conn.tables.flat_map { |t| conn.foreign_keys(t).select { |fk| fk.to_table == "users" } }

      destroy_assocs = User.reflect_on_all_associations.select do |assoc|
        assoc.options[:dependent].in?(%i[destroy delete_all])
      end.map { |a| [a.table_name, a.foreign_key.to_s] }.to_set

      nullify_assocs = User.reflect_on_all_associations.select do |assoc|
        assoc.options[:dependent] == :nullify
      end

      handled_assocs = (destroy_assocs + nullify_assocs.map { |a| [a.table_name, a.foreign_key.to_s] }).to_set

      unhandled_fks = user_fks.reject do |fk|
        pair = [fk.from_table, fk.column.to_s]
        next true if admin_actor_foreign_keys.include?(pair)
        next true if pending_foreign_keys.include?(pair)
        next true if fk.on_delete == :cascade
        next true if destroy_assocs.include?(pair)

        if fk.on_delete == :nullify
          allowed_nullify_keys.include?(pair)
        else
          handled_assocs.include?(pair)
        end
      end.map { |fk| "#{fk.from_table}.#{fk.column}" }

      disallowed_assocs = nullify_assocs.reject do |assoc|
        allowed_nullify_associations.include?(assoc.name)
      end.map(&:name).map(&:to_s)

      offenses = unhandled_fks + disallowed_assocs

      expect(offenses).to be_empty, "Unhandled foreign keys or disallowed nullify associations: #{offenses.join(", ")}"
    end
  end
end
