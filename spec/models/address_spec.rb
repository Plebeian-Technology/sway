# frozen_string_literal: true

# == Schema Information
#
# Table name: addresses
#
#  id                  :integer          not null, primary key
#  street              :string           not null
#  street_2            :string
#  street_3            :string
#  city                :string           not null
#  state_province_code :string           not null
#  postal_code         :string           not null
#  country             :string           default("US"), not null
#  latitude            :float
#  longitude           :float
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#
# typed: true

require 'rails_helper'

RSpec.describe Address, type: :model do
  describe '#from_string' do
    let(:address) do
      address_string = '1 East Baltimore St, Baltimore, MD, 21202'

      address = Address.from_string(address_string)
    end

    context 'when a user submits a form with an address' do
      it 'creates Address object from the form data strings' do
        expect(address).to be_truthy
        expect(address&.state_province_code).to match('MD')
      end
    end
  end

  describe '#geocode' do
    let(:address) do
      Address.new(
        street: Faker::Address.street_address(include_secondary: false),
        city: Faker::Address.city,
        state_province_code: Faker::Address.state_abbr,
        postal_code: Faker::Address.postcode
      )
    end

    context 'when an address is created with either no latitude, no longitude or neither' do
      it 'sets the latitude and longitude of the address' do
        expect(address.latitude).to be_nil
        expect(address.longitude).to be_nil

        address.validate!

        expect(address.latitude).to be_truthy
        expect(address.longitude).to be_truthy
      end
    end
  end
end
