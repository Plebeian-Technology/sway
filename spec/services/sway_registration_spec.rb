# typed: true
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SwayRegistrationService do
  describe '#build_user_legislators' do
    # let(:address) do
    #   address_string = '1 East Baltimore St, Baltimore, MD, 21202'

    #   address = Address.from_string(address_string)
    # end

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

      let(:sway_registration_service) do
        SwayRegistrationService.new(
          user,
          address
        )
      end

      it 'creates new UserLegislators if none exist' do
        expect { sway_registration_service.run }.to change(UserLegislator, :count).by_at_least(1)
      end
    end
  end
end
