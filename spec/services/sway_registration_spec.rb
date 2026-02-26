# typed: true
# frozen_string_literal: true

RSpec.describe SwayRegistrationService do
  describe "#run" do
    context "the service is run" do
      congress_json = JSON.parse(File.read("spec/support/files/congress.json"))

      it "creates new UserLegislators if none exist" do
        allow_any_instance_of(Census::Congress).to receive(:request).and_return(
          congress_json,
        )

        user = create(:user)

        address =
          create(
            :address,
            street: "1 East Baltimore St",
            city: "Baltimore",
            region_code: "MD",
            postal_code: "21202",
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
            create(:legislator, district:)

            sway_registration_service =
              SwayRegistrationService.new(user, address, s, invited_by_id: nil)

            expect { sway_registration_service.run }.to change(
              UserLegislator,
              :count,
            ).by(1)
          end
      end

      it "creates an Invite between two users when an invited_by_id (user_id) is passed" do
        allow_any_instance_of(Census::Congress).to receive(:request).and_return(
          congress_json,
        )
        address =
          create(
            :address,
            street: "1 East Baltimore St",
            city: "Baltimore",
            region_code: "MD",
            postal_code: "21202",
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
            postal_code: "21202",
          )
        _invited_user_user_address =
          create(
            :user_address,
            user: invited_user,
            address: invited_user_address,
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
            create(:legislator, district:)

            sway_registration_service =
              SwayRegistrationService.new(
                invited_user,
                invited_user_address,
                s,
                invited_by_id: user.id,
              )

            expect { sway_registration_service.run }.to change(
              Invite,
              :count,
            ).by(i == 0 ? 1 : 0)

            expect(Invite.last&.inviter).to eq(user)
            expect(Invite.last&.invitee).to eq(invited_user)
          end
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
        )

        SwayRegistrationService.new(
          user,
          address,
          sway_locale,
          invited_by_id: nil,
          async: true,
        ).run

        expect(user.registration_status).to eq("processing")
      end

      it "does not enqueue job and processes synchronously when async is false" do
        user = create(:user)
        address = create(:address)
        sway_locale = create(:sway_locale)
        allow(sway_locale).to receive(:regional?).and_return(true)

        # Mocking the actual processing logic to avoid external API calls
        allow_any_instance_of(SwayRegistrationService).to receive(
          :create_user_legislators,
        ).and_return([double(UserLegislator)])
        allow_any_instance_of(SwayRegistrationService).to receive(
          :create_invite,
        ).and_return(nil)

        expect(SwayRegistrationJob).not_to receive(:perform_later)

        SwayRegistrationService.new(
          user,
          address,
          sway_locale,
          invited_by_id: nil,
          async: false,
        ).run

        expect(user.registration_status).to eq("completed")
      end
    end
  end
end
