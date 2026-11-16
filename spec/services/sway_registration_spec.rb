# frozen_string_literal: true

RSpec.describe SwayRegistrationService do
  def create_supported_term(legislator:, district:, office_identity: "test-registration-office")
    seat = Seat.find_or_create_by_identity!(
      district:,
      office_identity:,
      title: "Test representative",
      chamber: "House"
    )
    create(:legislator_term, legislator:, district:, seat:)
  end

  describe "#call" do
    context "the service is run" do
      congress_json = JSON.parse(File.read("spec/support/files/congress.json"))

      it "creates new UserLegislators if none exist" do
        allow_any_instance_of(Census::Congress).to receive(:request).and_return(
          # Census::Congress#data no longer shortcuts a Hash request; it parses
          # request.body as JSON like a real Faraday response, so hand it a
          # fake whose body is the fixture as JSON.
          double(body: congress_json.to_json)
        )

        user = create(:user)

        address =
          create(
            :address,
            street: "1 East Baltimore St",
            city: "Baltimore",
            region_code: "MD",
            postal_code: "21202"
          )
        _user_address = create(:user_address, user:, address:)

        address
          .sway_locales
          .filter { |s| s.congress? || s.has_geojson? }
          .each do |s|
            name =
              (
                if s.congress?
                  "#{address.region_code}7"
                else
                  "#{address.region_code}0"
                end
              )
            district =
              District.find_by(sway_locale: s, name:) ||
              create(:district, sway_locale: s, name:)
            legislator = create(:legislator, district:)
            create_supported_term(legislator:, district:)

            sway_registration_service =
              SwayRegistrationService.new(user, address, s, invited_by_id: nil)

            expect { sway_registration_service.call }.to change(
              UserLegislator,
              :count
            ).by(1)
          end
      end

      it "creates an Invite between two users when an invited_by_id (user_id) is passed" do
        allow_any_instance_of(Census::Congress).to receive(:request).and_return(
          # Census::Congress#data no longer shortcuts a Hash request; it parses
          # request.body as JSON like a real Faraday response, so hand it a
          # fake whose body is the fixture as JSON.
          double(body: congress_json.to_json)
        )
        address =
          create(
            :address,
            street: "1 East Baltimore St",
            city: "Baltimore",
            region_code: "MD",
            postal_code: "21202"
          )
        user = create(:user)
        _user_address = create(:user_address, user:, address:)

        invited_user = create(:user)
        invited_user_address =
          create(
            :address,
            street: "2 East Baltimore St",
            city: "Baltimore",
            region_code: "MD",
            postal_code: "21202"
          )
        _invited_user_user_address =
          create(
            :user_address,
            user: invited_user,
            address: invited_user_address
          )

        address
          .sway_locales
          .filter { |s| s.congress? || s.has_geojson? }
          .each_with_index do |s, i|
            name =
              (
                if s.congress?
                  "#{address.region_code}7"
                else
                  "#{address.region_code}0"
                end
              )
            district =
              District.find_by(sway_locale: s, name:) ||
              create(:district, sway_locale: s, name:)
            legislator = create(:legislator, district:)
            create_supported_term(legislator:, district:)

            sway_registration_service =
              SwayRegistrationService.new(
                invited_user,
                invited_user_address,
                s,
                invited_by_id: user.id
              )

            expect { sway_registration_service.call }.to change(
              Invite,
              :count
            ).by((i == 0) ? 1 : 0)

            expect(Invite.last&.inviter).to eq(user)
            expect(Invite.last&.invitee).to eq(invited_user)
          end
      end

      # The unique index used to cover inviter_id alone, so the SECOND person
      # registering through one inviter's link hit RecordNotUnique inside
      # create_invite and was cut short. Both must finish now.
      it "records an Invite for each of two invitees sharing one inviter" do
        allow_any_instance_of(Census::Congress).to receive(:request).and_return(
          # Census::Congress#data no longer shortcuts a Hash request; it parses
          # request.body as JSON like a real Faraday response, so hand it a
          # fake whose body is the fixture as JSON.
          double(body: congress_json.to_json)
        )

        inviter = create(:user)
        invitees = create_list(:user, 2)

        invitees.each do |invitee|
          address =
            create(
              :address,
              street: "#{invitee.id} East Baltimore St",
              city: "Baltimore",
              region_code: "MD",
              postal_code: "21202"
            )
          create(:user_address, user: invitee, address: address)

          congress_locale = address.sway_locales.find(&:congress?)
          district =
            District.find_by(sway_locale: congress_locale, name: "MD7") ||
            create(:district, sway_locale: congress_locale, name: "MD7")
          legislator = district.legislator_terms.first&.legislator || create(:legislator, district: district)
          legislator.active_term || create_supported_term(legislator:, district:)

          SwayRegistrationService.new(
            invitee,
            address,
            congress_locale,
            invited_by_id: inviter.id
          ).call
        end

        expect(Invite.where(inviter: inviter).count).to eq(2)
        expect(Invite.where(inviter: inviter).map(&:invitee)).to match_array(
          invitees
        )
      end

      # Our services return the objects they created, so create_user_legislators
      # must hand back the saved UserLegislator records — NOT the array of
      # `true` values that `ul.save!` used to return.
      it "returns the persisted UserLegislator records from create_user_legislators" do
        allow_any_instance_of(Census::Congress).to receive(:request).and_return(
          double(body: congress_json.to_json)
        )

        user = create(:user)
        address =
          create(
            :address,
            street: "1 East Baltimore St",
            city: "Baltimore",
            region_code: "MD",
            postal_code: "21202"
          )
        create(:user_address, user: user, address: address)

        congress_locale = address.sway_locales.find(&:congress?)
        next if congress_locale.nil?

        district =
          District.find_by(sway_locale: congress_locale, name: "MD7") ||
          create(:district, sway_locale: congress_locale, name: "MD7")
        legislator = district.legislator_terms.first&.legislator || create(:legislator, district: district)
        legislator.active_term || create_supported_term(legislator:, district:)

        result =
          SwayRegistrationService.new(
            user,
            address,
            congress_locale,
            invited_by_id: nil
          ).create_user_legislators

        expect(result).to be_present
        expect(result).to all(be_a(UserLegislator))
        expect(result).to all(be_persisted)
      end
    end

    context "when geocoding fails" do
      it "propagates the error and creates no UserLegislator" do
        allow_any_instance_of(Census::Congress).to receive(:request).and_raise(
          StandardError,
          "geocode failed"
        )

        user = create(:user, is_registration_complete: false)
        address =
          create(
            :address,
            street: "1 East Baltimore St",
            city: "Baltimore",
            region_code: "MD",
            postal_code: "21202"
          )
        _user_address = create(:user_address, user:, address:)
        sway_locale = address.sway_locales.find { |s| s.congress? }

        next if sway_locale.nil?

        # Create a legislator so @legislators is not empty and
        # district_legislators reaches the `districts.include?(...)` branch,
        # which is where SwayGeocode.build calls Census::Congress#request.
        district =
          District.find_by(sway_locale: sway_locale, name: "MD7") ||
          create(:district, sway_locale: sway_locale, name: "MD7")
        legislator = create(:legislator, district: district)
        create(:legislator_term, legislator:, district:)

        service =
          SwayRegistrationService.new(
            user,
            address,
            sway_locale,
            invited_by_id: nil
          )

        expect { service.call }.to raise_error(StandardError, /geocode failed/)
        expect(UserLegislator.where(user: user).count).to eq(0)
      end

      it "records a Census connection failure as a skipped SwayGeocode::ServiceUnavailableError" do
        allow(Sentry).to receive(:capture_exception)
        allow_any_instance_of(Census::Congress).to receive(:request).and_raise(
          Faraday::ConnectionFailed,
          "Failed to open TCP connection to tigerweb.geo.census.gov:443"
        )

        user = create(:user, is_registration_complete: false)
        address =
          create(
            :address,
            street: "1 East Baltimore St",
            city: "Baltimore",
            region_code: "MD",
            postal_code: "21202"
          )
        _user_address = create(:user_address, user:, address:)
        sway_locale = address.sway_locales.find { |s| s.congress? }

        next if sway_locale.nil?

        district =
          District.find_by(sway_locale: sway_locale, name: "MD7") ||
          create(:district, sway_locale: sway_locale, name: "MD7")
        legislator = create(:legislator, district: district)
        create(:legislator_term, legislator:, district:)

        service =
          SwayRegistrationService.new(
            user,
            address,
            sway_locale,
            invited_by_id: nil
          )

        service.call

        expect(service.skipped_resolution_errors).to contain_exactly(
          an_instance_of(SwayGeocode::ServiceUnavailableError)
            .and(having_attributes(message: /Census TIGERweb geocoding is unavailable/))
        )
        expect(UserLegislator.where(user: user).count).to eq(0)
      end

      it "ignores locale legislators with no active_term when collecting state_house_legislator_ids" do
        allow(Sentry).to receive(:capture_exception)
        allow_any_instance_of(Census::Congress).to receive(:request).and_raise(
          Faraday::ConnectionFailed,
          "Failed to open TCP connection"
        )

        user = create(:user, is_registration_complete: false)
        address = create(:address, street: "1 East Baltimore St", city: "Baltimore", region_code: "MD", postal_code: "21202")
        create(:user_address, user:, address:)
        sway_locale = address.sway_locales.find(&:congress?)
        next if sway_locale.nil?

        district = District.find_by(sway_locale:, name: "MD7") || create(:district, sway_locale:, name: "MD7")
        _termless = create(:legislator, district:, sway_locale:)
        service = SwayRegistrationService.new(user, address, sway_locale, invited_by_id: nil)

        expect { service.call }.not_to raise_error
        expect(service.skipped_legislator_ids).to eq([])
      end
    end

    describe "invite creation and office checks" do
      it "skips invite creation when invited_by_id matches no user and rescues self-invite validation errors" do
        user = create(:user, is_registration_complete: false)
        sway_locale = create(:sway_locale, :baltimore)
        district = District.find_by(sway_locale:, name: "MD0") || create(:district, sway_locale:, name: "MD0")
        seat = Seat.find_or_create_by_identity!(
          district:,
          office_identity: "test-invite-office",
          title: "Mayor",
          chamber: "Executive"
        )
        legislator = create(:legislator, district:, sway_locale:)
        create(:legislator_term, legislator:, district:, seat:)
        address = create(:address, street: "100 Main", city: "Baltimore", region_code: "MD", postal_code: "21202")
        create(:user_address, user:, address:)

        allow(SwayGeocode).to receive(:build).and_return(instance_double(SwayGeocode::Local, districts: [0]))

        expect {
          SwayRegistrationService.new(user, address, sway_locale, invited_by_id: -1).call
        }.not_to change(Invite, :count)

        allow(SwayLogging).to receive(:log_exception)
        expect {
          SwayRegistrationService.new(user, address, sway_locale, invited_by_id: user.id).call
        }.not_to change(Invite, :count)
        expect(SwayLogging).to have_received(:log_exception).with("sway_registration.create_invite_failed", any_args)
      end

      it "treats blank-title unseated terms and undeclared-locale terms as not unconfigured offices" do
        user = create(:user, is_registration_complete: false)
        undeclared = create(:sway_locale, city: "undeclared_office_city", state: "MD", country: "US")
        district = create(:district, sway_locale: undeclared, name: "MD0")
        legislator = create(:legislator, district:, sway_locale: undeclared)
        term_with_title = create(:legislator_term, legislator:, district:, title: "Commissioner")
        term_without_title = create(:legislator_term, legislator: create(:legislator, district:, sway_locale: undeclared), district:, title: nil)
        address = create(:address)

        service = SwayRegistrationService.new(user, address, undeclared, invited_by_id: nil)

        expect(service.send(:unseated_unconfigured_office?, term_without_title)).to be(false)
        expect(service.send(:unseated_unconfigured_office?, term_with_title)).to be(false)
      end
    end
  end
end
