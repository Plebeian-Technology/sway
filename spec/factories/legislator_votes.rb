# == Schema Information
#
# Table name: legislator_votes
# Database name: primary
#
#  id                 :integer          not null, primary key
#  inferred           :boolean          default(FALSE), not null
#  source             :string           not null
#  support            :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  bill_id            :integer          not null
#  legislator_id      :integer          not null
#  legislator_term_id :integer          not null
#
# Indexes
#
#  index_legislator_votes_on_bill_and_person_null_term_unique  (bill_id,legislator_id) UNIQUE WHERE legislator_term_id IS NULL
#  index_legislator_votes_on_bill_and_term_unique              (bill_id,legislator_term_id) UNIQUE WHERE legislator_term_id IS NOT NULL
#  index_legislator_votes_on_bill_id                           (bill_id)
#  index_legislator_votes_on_legislator_id                     (legislator_id)
#  index_legislator_votes_on_legislator_term_id                (legislator_term_id)
#
# Foreign Keys
#
#  bill_id             (bill_id => bills.id)
#  legislator_id       (legislator_id => legislators.id)
#  legislator_term_id  (legislator_term_id => legislator_terms.id)
#
FactoryBot.define do
  factory :legislator_vote do
    # @type self: LegislatorVoteFactoryContext
    bill
    legislator { legislator_term&.legislator || association(:legislator) }
    transient do
      legislator_term { nil }
    end
    legislator_term_id do
      (legislator_term || legislator.terms.find_by(term_start_year: 2025) ||
        association(:legislator_term, legislator: legislator,
          district: legislator.district || association(:district, sway_locale: legislator.sway_locale, strategy: :create),
          strategy: :create)).id
    end
    support { LegislatorVote::Support::FOR }
    source { "manual" }
    inferred { false }

    initialize_with { new({bill:, legislator:, legislator_term_id:, support:, source:, inferred:}) }

    trait :for do
      support { LegislatorVote::Support::FOR }
    end

    trait :against do
      support { LegislatorVote::Support::AGAINST }
    end

    trait :abstain do
      support { LegislatorVote::Support::ABSTAIN }
    end

    # Rows worked out from sponsorship rather than from a recorded vote. They
    # look just like real roll-call votes apart from this marker, and the
    # interesting-score math leaves them out when counting defections,
    # abstentions and close margins.
    trait :inferred do
      inferred { true }
    end
  end
end
