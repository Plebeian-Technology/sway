# typed: true
# frozen_string_literal: true

# == Schema Information
#
# Table name: sway_locales
#
#  id         :integer          not null, primary key
#  city       :string           not null
#  state      :string           not null
#  country    :string           default("United States"), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null

RSpec.describe SwayLocale, type: :model do
  describe '#name' do
    context 'when #name is called' do
      it 'constructs a name from the city, state and country names' do
        sway_locale = lambda do
          SwayLocale.new(
            city: 'Baltimore',
            state: 'Maryland',
            country: 'United States'
          )
        end.call

        expect(sway_locale.name).to eq('baltimore-maryland-united_states')
      end

      it 'constructs a name from the city, state code and country code' do
        sway_locale = lambda do
          SwayLocale.new(
            city: 'Baltimore',
            state: 'MD',
            country: 'US'
          )
        end.call

        expect(sway_locale.name).to eq('baltimore-maryland-united_states')
      end
    end
  end

  describe '#load_geojson' do
    context 'when a geojson file is requested' do
      it 'loads the geojson file corresponding to its name' do
        sway_locale = lambda do
          SwayLocale.new(
            city: 'Baltimore',
            state: 'MD',
            country: 'US'
          )
        end.call

        expect(sway_locale.load_geojson).to be_truthy
      end
    end
  end

  describe '#legislators' do
    context 'when a sway_locale accesses its Legislators' do
      it 'reads the Legislators via the Districts associated with self' do
        sway_locale = lambda do
          SwayLocale.find_or_create_by_normalized!(
            city: 'Baltimore',
            state: 'MD',
            country: 'US'
          )
        end.call

        expect(sway_locale.legislators.empty?).to be false
      end
    end
  end
end
