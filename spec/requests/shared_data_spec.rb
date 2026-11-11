# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Inertia shared data", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  def complete_registration(user)
    create(:user_legislator, user: user) unless user.registered?
    user.complete!
  end

  describe "flash" do
    it "shares flash messages as a hash" do
      _sway_locale, user = setup_pre_registration
      complete_registration(user)

      get legislators_path
      expect(inertia).to have_props { |p| p[:flash].is_a?(Hash) }
    end
  end

  describe "user data" do
    it "keeps the completion key boolean and derives it from active pairings" do
      _sway_locale, user = setup
      user.update_columns(registration_status: "completed", is_registration_complete: false)

      get legislators_path

      user_data = inertia.props[:user]
      expect(user_data).to have_key(:is_registration_complete)
      expect(user_data[:is_registration_complete]).to be(true)
      expect(user.reload.is_registration_complete).to be(true)
    end

    context "when signed in" do
      it "shares current user data" do
        _sway_locale, user = setup_pre_registration
        complete_registration(user)

        get legislators_path
        expect(inertia).to have_props { |p| p[:user].present? }
      end

      # @lat: [[identity-and-access#Identity and access#User JSON exposes only selected fields]]
      it "does not expose sensitive user fields (login IPs, webauthn_id, sign_in_count, is_admin)" do
        _sway_locale, user = setup_pre_registration
        complete_registration(user)
        # Point ADMIN_PHONES at a different number, so this user is reliably a
        # non-admin and is_admin is the absent case.
        User.send(:remove_const, :ADMIN_PHONES)
        User.const_set(:ADMIN_PHONES, ["+10000000000"])

        get legislators_path

        user_data = inertia.props[:user] || {}
        # password_digest never existed as a column; the rest are real columns
        # to_builder deliberately leaves out. Check both symbol and string keys.
        %w[password_digest current_sign_in_ip last_sign_in_ip webauthn_id sign_in_count is_admin].each do |field|
          expect(user_data).not_to have_key(field.to_sym)
          expect(user_data).not_to have_key(field)
        end
      end

      # @lat: [[identity-and-access#Identity and access#User JSON exposes only selected fields#Shared address props use an explicit field list]]
      it "does not expose latitude/longitude or street3 on user.address" do
        _sway_locale, user = setup
        address = create(:address, latitude: 38.9072, longitude: -77.0369)
        create(:user_address, user: user, address: address)

        get legislators_path

        address_data = (inertia.props[:user] || {})[:address] || {}
        expect(address_data).not_to have_key(:latitude)
        expect(address_data).not_to have_key("latitude")
        expect(address_data).not_to have_key(:longitude)
        expect(address_data).not_to have_key("longitude")
        expect(address_data).not_to have_key(:street3)
        expect(address_data).not_to have_key("street3")
      end
    end

    context "when not signed in" do
      it "shares nil user" do
        get root_path
        expect(inertia).to have_props(user: nil)
      end
    end
  end

  describe "locale data" do
    it "shares sway_locale" do
      _sway_locale, user = setup_pre_registration
      complete_registration(user)

      get legislators_path
      expect(inertia).to have_props { |p| p.key?(:sway_locale) }
    end

    it "shares sway_locales array" do
      _sway_locale, user = setup_pre_registration
      complete_registration(user)

      get legislators_path
      expect(inertia).to have_props { |p| p[:sway_locales].is_a?(Array) }
    end

    it "shares sway_locale_options as {label:, value:} pairs" do
      _sway_locale, user = setup_pre_registration
      complete_registration(user)

      get legislators_path
      expect(inertia).to have_props { |p|
        options = p[:sway_locale_options]
        options.is_a?(Array) &&
          options.all? { |o| (o[:label] || o["label"]).present? && (o[:value] || o["value"]).present? }
      }
    end

    # @lat: [[identity-and-access#Identity and access#User JSON exposes only selected fields#Locale props are never cached once per browser]]
    describe "per-user locale props are never client-cached" do
      %i[sway_locales sway_locale_options admin_sway_locale_options].each do |prop|
        it "ships #{prop} even when the client claims it already has it" do
          sway_locale, user = setup
          address = create(:address, city: sway_locale.city, region_code: sway_locale.state,
            country: sway_locale.country)
          create(:user_address, user: user, address: address)

          get legislators_path, headers: {
            "X-Inertia" => "true",
            "X-Inertia-Version" => InertiaRails.configuration.version,
            "X-Inertia-Except-Once-Props" => "sway_locales,sway_locale_options,admin_sway_locale_options"
          }

          expect(response).to have_http_status(:ok)
          expect(inertia.props).to have_key(prop)
        end
      end

      it "declares no once-props at all on this response" do
        sway_locale, user = setup
        address = create(:address, city: sway_locale.city, region_code: sway_locale.state, country: sway_locale.country)
        create(:user_address, user: user, address: address)

        get legislators_path, headers: {
          "X-Inertia" => "true",
          "X-Inertia-Version" => InertiaRails.configuration.version
        }

        # onceProps is how the server tells the client which keys to cache. An
        # empty or missing map leaves nothing to poison, so this check catches
        # `once` coming back anywhere in the shared-props block, not only on
        # the three keys above.
        expect(JSON.parse(response.body).fetch("onceProps", {})).to eq({})
      end
    end

    # The picker in the navigation bar (sway_locales and sway_locale_options)
    # lists only the current user's OWN locales, admins included. The full list
    # the admin Bill Creator needs travels separately, in the admin-only
    # admin_sway_locale_options prop.
    describe "locale scope by role" do
      def shared_locale_ids
        (inertia.props[:sway_locales] || []).map { |l| l[:id] || l["id"] }
      end

      def shared_option_values
        (inertia.props[:sway_locale_options] || []).map { |o| o[:value] || o["value"] }
      end

      def admin_option_values
        (inertia.props[:admin_sway_locale_options] || []).map { |o| o[:value] || o["value"] }
      end

      it "scopes the nav selector to the admin's own locales, not every locale" do
        sway_locale, user = setup
        address = create(:address, city: sway_locale.city, region_code: sway_locale.state, country: sway_locale.country)
        create(:user_address, user: user, address: address)
        other = create(:sway_locale, city: "annapolis", state: "MD", country: "United States")

        get legislators_path

        expect(shared_locale_ids).to include(sway_locale.id)
        expect(shared_locale_ids).not_to include(other.id)
        expect(shared_option_values).not_to include(other.id)
      end

      it "exposes only declared locales to admins via admin_sway_locale_options" do
        sway_locale, user = setup
        address = create(:address, city: sway_locale.city, region_code: sway_locale.state, country: sway_locale.country)
        create(:user_address, user: user, address: address)
        declared_other = create(:sway_locale, city: "annapolis", state: "MD", country: "United States")
        other = create(:sway_locale, city: "bethesda", state: "MD", country: "United States")

        get legislators_path

        expect(shared_locale_ids).to include(sway_locale.id)
        expect(shared_locale_ids).not_to include(declared_other.id, other.id)
        expect(shared_option_values).to include(sway_locale.id)
        expect(shared_option_values).not_to include(declared_other.id, other.id)
        expect(admin_option_values).to include(sway_locale.id, declared_other.id)
        expect(admin_option_values).not_to include(other.id)
      end

      it "limits non-admins to their own address locales and ships no admin locale list" do
        sway_locale, user = setup
        address = create(:address, city: sway_locale.city, region_code: sway_locale.state, country: sway_locale.country)
        create(:user_address, user: user, address: address)
        other = create(:sway_locale, city: "annapolis", state: "MD", country: "United States")
        # setup makes its user an admin by putting their phone in ADMIN_PHONES.
        # Swap the constant again here to take that away.
        User.send(:remove_const, :ADMIN_PHONES)
        User.const_set(:ADMIN_PHONES, ["+19999999999"])

        get legislators_path

        expect(shared_locale_ids).to include(sway_locale.id)
        expect(shared_locale_ids).not_to include(other.id)
        expect(shared_option_values).to include(sway_locale.id)
        expect(shared_option_values).not_to include(other.id)
        expect(inertia.props[:admin_sway_locale_options]).to be_nil
      end
    end

    context "when not signed in" do
      def shared_locale_ids
        (inertia.props[:sway_locales] || []).map { |l| l[:id] || l["id"] }
      end

      def shared_option_values
        (inertia.props[:sway_locale_options] || []).map { |o| o[:value] || o["value"] }
      end

      it "shares declared locales and excludes undeclared locales in sway_locales and sway_locale_options" do
        declared_locale = create(:sway_locale, :baltimore)
        undeclared_locale = create(:sway_locale, city: "bethesda", state: "MD", country: "United States")

        get root_path

        expect(inertia).to render_component(Pages::HOME)
        expect(shared_locale_ids).to include(declared_locale.id)
        expect(shared_locale_ids).not_to include(undeclared_locale.id)
        expect(shared_option_values).to include(declared_locale.id)
        expect(shared_option_values).not_to include(undeclared_locale.id)
      end
    end
  end

  describe "params" do
    it "shares params with only the sway_locale_id key (no reflected errors)" do
      _sway_locale, user = setup_pre_registration
      complete_registration(user)

      get legislators_path
      # The shared params carry sway_locale_id but no longer echo
      # params[:errors]. Nothing read it, and a crafted ?errors= link could
      # push arbitrary text into the page's props.
      expect(inertia).to have_props { |p|
        params_prop = p[:params] || {}
        params_prop.key?(:sway_locale_id) && !params_prop.key?(:errors)
      }
    end
  end
end
