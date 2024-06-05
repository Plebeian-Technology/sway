# typed: true
# frozen_string_literal: true

RSpec.describe CongressLegislatorVoteUpdateService do
  describe '#run' do
    context 'a new Bill is created' do
      CONGRESS = {
        city: 'congress',
        state: 'congress',
        country: 'united_states'
      }

      it 'creates new LegislatorVotes for both the house and senate' do
        expect(LegislatorVote.count).to eql(0)

        address = build(:address, region_code: 'MD')
        sway_locale = build(
          :sway_locale,
          CONGRESS
        )

        district = build(:district, sway_locale:)

        senator = build(:legislator, address:, district:, title: 'Sen.', external_id: 'V000128', first_name: 'Chris',
                                     last_name: 'Van Hollen')
        representative = build(:legislator, address:, district:, first_name: 'Kweisi', last_name: 'Mfume',
                                            external_id: 'M000687', title: 'Rep.')

        bill = build(:bill, sway_locale:, external_id: 'hr815')
        create(:vote, bill:)

        expect(LegislatorVote.count).to eql(2)
        expect(LegislatorVote.where(legislator: senator).first&.support).to eql('FOR')
        expect(LegislatorVote.where(legislator: representative).first&.support).to eql('FOR')
      end
    end
  end
end
