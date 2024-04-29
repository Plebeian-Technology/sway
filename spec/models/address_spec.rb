# typed: true
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Address, type: :model do
  describe '#from_string' do
    context 'when a user submits a form with an address' do
      it 'creates Address object from the form data strings' do
        address_string = '1 East Baltimore St, Baltimore, MD, 21202'

        address = Address.from_string(address_string)
        expect(address).to be_truthy
        expect(address&.state_province_code).to match('MD')
      end
    end
  end

  describe '#geocode' do
    context 'when an address is created with either no latitude, no longitude or neither' do
      it 'sets the latitude and longitude of the address' do
        address = Address.new(
          street: Faker::Address.street_address(include_secondary: false),
          city: Faker::Address.city,
          state_province_code: Faker::Address.state_abbr,
          postal_code: Faker::Address.postcode
        )

        expect(address.latitude).to be_nil
        expect(address.longitude).to be_nil

        address.validate!

        expect(address.latitude).to be_truthy
        expect(address.longitude).to be_truthy
      end
    end
  end
end
