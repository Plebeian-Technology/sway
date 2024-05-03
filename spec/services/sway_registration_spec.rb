# typed: true
# frozen_string_literal: true

RSpec.describe SwayRegistrationService do
  describe '#run' do
    context 'the service is run' do
      let(:user) do
        User.find_or_create_by!(phone: Faker::PhoneNumber.cell_phone)
      end

      let(:address) do
        address_string = '1 East Baltimore St, Baltimore, MD, 21202'
        Address.from_string(address_string)
      end

      let(:user_address) do
        UserAddress.new(
          user:,
          address:
        )
      end


      it 'creates new UserLegislators if none exist' do
        address.sway_locales.filter { |s| s.is_congress? || s.has_geojson? }.each do |s|

          sway_registration_service = SwayRegistrationService.new(
            user,
            address,
            s
          )

          allow_any_instance_of(Census::Congress).to receive(:request).and_return(JSON.parse(File.read("spec/support/files/congress.json")))

          expect { sway_registration_service.run }.to change(UserLegislator, :count).by(3)
        end
      end
    end
  end
end
