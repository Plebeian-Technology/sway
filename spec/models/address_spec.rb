# frozen_string_literal: true

# == Schema Information
#
# Table name: addresses
#
#  id          :integer          not null, primary key
#  street      :string           not null
#  street_2    :string
#  street_3    :string
#  city        :string           not null
#  region_code :string           not null
#  postal_code :string           not null
#  country     :string           default("US"), not null
#  latitude    :float
#  longitude   :float
#  created_at  :datetime         not null
#  updated_at  :datetime         not null

RSpec.describe Address, type: :model do
  describe '#from_string' do
    let(:address) do
      address_string = '1 East Baltimore St, Baltimore, MD, 21202'

      Address.from_string(address_string)
    end

    context 'when a user submits a form with an address' do
      it 'creates Address object from the form data strings' do
        expect(address).to be_truthy
        expect(address&.region_code).to match('MD')
      end
    end
  end

  describe '#geocode' do
    let(:address) do
      Address.new(
        street: Faker::Address.street_address(include_secondary: false),
        city: Faker::Address.city,
        region_code: Faker::Address.state_abbr,
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

  describe '#sway_locale' do
    context 'what an address accesses its sway_locale' do
      let(:address) do
        Address.new(
          street: Faker::Address.street_address(include_secondary: false),
          city: Faker::Address.city,
          region_code: Faker::Address.state_abbr,
          postal_code: Faker::Address.postcode
        )
      end

      it 'returns a SwayLocale, creating it if necessary' do
        start_sway_locale_count = SwayLocale.count
        sway_locales = address.sway_locales
        end_sway_locale_count = start_sway_locale_count + 2

        expect(SwayLocale.count).to equal end_sway_locale_count

        expect(address.sway_locales.present?).to be_truthy

        # address.sway_locales.each do |sway_locale|
        #   # https://api.rubyonrails.org/classes/ActiveRecord/Persistence.html#method-i-previously_new_record-3F
        #   # Returns true if this object was just created – that is, prior to the last update or delete, the object didn’t exist in the database and new_record? would have returned true.
        #   # expect(sway_locale.previously_new_record?).to be true


        #   expect(SwayLocale.count).to equal end_sway_locale_count

        #   expect(sway_locale).to eq address.sway_locale
        # end

      end
    end
  end
end
