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
            invited_by_id: inviter.id,
            async: false
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
            invited_by_id: nil,
            async: false
          ).create_user_legislators

        expect(result).to be_present
        expect(result).to all(be_a(UserLegislator))
        expect(result).to all(be_persisted)
      end
    end

    context "when geocoding fails" do
      # NOTE: an earlier draft expected the service to move the user to
      # :failed on a geocoding error. It does not catch errors —
      # SwayRegistrationJob rescues and calls mark_failed!.
      it "propagates the error and creates no UserLegislator when async is false" do
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
            invited_by_id: nil,
            async: false
          )

        expect { service.call }.to raise_error(StandardError, /geocode failed/)
        expect(UserLegislator.where(user: user).count).to eq(0)
      end

      it "translates a Census connection failure into SwayGeocode::ServiceUnavailableError" do
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
            invited_by_id: nil,
            async: false
          )

        expect { service.call }.to raise_error(
          SwayGeocode::ServiceUnavailableError,
          /Census TIGERweb geocoding is unavailable/
        )
        expect(UserLegislator.where(user: user).count).to eq(0)
      end
    end

    context "regional registration" do
      it "enqueues SwayRegistrationJob and sets user to processing status when async is true" do
        user = create(:user)
        address = create(:address)
        sway_locale = create(:sway_locale)
        allow(sway_locale).to receive(:regional?).and_return(true)

        expect(SwayRegistrationJob).to receive(:perform_later).with(
          user.id,
          address.id,
          sway_locale.id,
          invited_by_id: nil,
          enqueued_at_epoch: a_kind_of(Float)
        )

        SwayRegistrationService.new(
          user,
          address,
          sway_locale,
          invited_by_id: nil,
          async: true
        ).call

        expect(user.registration_status).to eq("processing")
      end

      it "does not enqueue job and processes synchronously when async is false" do
        user = create(:user)
        address = create(:address)
        sway_locale = create(:sway_locale)
        allow(sway_locale).to receive(:regional?).and_return(true)

        # Replace the real processing so nothing calls an external API.
        allow_any_instance_of(SwayRegistrationService).to receive(
          :create_user_legislators
        ) do
          [create(:user_legislator, user: user)]
        end
        allow_any_instance_of(SwayRegistrationService).to receive(
          :create_invite
        ).and_return(nil)

        expect(SwayRegistrationJob).not_to receive(:perform_later)

        SwayRegistrationService.new(
          user,
          address,
          sway_locale,
          invited_by_id: nil,
          async: false
        ).call

        expect(user.registration_status).to eq("completed")
      end
    end
  end
end
