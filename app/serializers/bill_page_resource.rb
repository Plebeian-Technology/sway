# frozen_string_literal: true

# @lat: [[system-shape#System shape#One process, two languages#The bill page composes a page payload from several contracts]]
class BillPageResource < ApplicationResource
  attribute :bill do |bill|
    -> { BillResource.new(bill).serializable_hash }
  end

  attribute :organizations do |bill|
    cache = organization_positions_cache
    # @lat: [[bills-controller-design#BillsController design#The bill page returns active organization positions as flat rows]]
    -> { BillPageResource.fetch_organization_positions(bill, cache) }
  end

  attribute :organization_bill_positions do |bill|
    cache = organization_positions_cache
    -> { BillPageResource.fetch_organization_positions(bill, cache) }
  end

  attribute :legislator_votes do |bill|
    InertiaRails.optional {
      bill.legislator_votes.map { |vote| LegislatorVoteResource.new(vote).serializable_hash }
    }
  end

  attribute :legislators do |bill|
    current_sway_locale = params[:current_sway_locale]
    InertiaRails.optional {
      if (session = bill.legislative_session)
        session.legislators.distinct.with_active_term.preload(photo_attachment: :blob)
          .map { |legislator| BillPageLegislatorResource.new(legislator).serializable_hash }
      else
        current_sway_locale&.legislators&.with_active_term&.preload(photo_attachment: :blob)
          &.map { |legislator| BillPageLegislatorResource.new(legislator).serializable_hash } || []
      end
    }
  end

  attribute :sponsor do |bill|
    -> { BillPageLegislatorResource.new(bill.legislator).serializable_hash }
  end

  attribute :user_vote do |bill|
    current_user = params[:current_user]
    -> {
      UserVote.find_by(user: current_user, bill_id: bill.id)&.then { |vote|
        UserVoteResource.new(vote).serializable_hash
      }
    }
  end

  attribute :bill_score do |bill|
    district_legislator_names = params[:district_legislator_names]
    -> {
      BillScore.includes(bill_score_districts: :district)
        .find_by(bill_id: bill.id)
        &.then { |score| BillScoreResource.new(score, params: {district_legislator_names:}).serializable_hash }
    }
  end

  attribute :districts do |bill|
    current_user = params[:current_user]
    bill_sway_locale = bill.sway_locale
    InertiaRails.optional {
      districts = current_user&.districts(bill_sway_locale)
      selected_districts = districts&.map { |district| BillPageDistrictResource.new(district).serializable_hash }
      selected_districts ||
        [bill_sway_locale&.at_large_district]
          .compact
          .map { |district| BillPageDistrictResource.new(district).serializable_hash }
    }
  end

  # @lat: [[testimony-letters#Reading the letters inside a testimony bundle#Presenting public testimony on bill pages#Signed-out readers receive no public testimony]]
  attribute :public_testimony_counts do |bill|
    cache = browsable_letters_cache
    signed_in = !params[:current_user].nil?
    -> {
      if signed_in
        entries = cache.fetch(bill.object_id) { cache[bill.object_id] = Testimony::BrowsableLetters.for_bill(bill) }
        Testimony::BrowsableLetters.counts_from_entries(entries)
      end
    }
  end

  attribute :public_testimony_letters do |bill|
    cache = browsable_letters_cache
    signed_in = !params[:current_user].nil?
    InertiaRails.optional {
      if signed_in
        entries = cache.fetch(bill.object_id) { cache[bill.object_id] = Testimony::BrowsableLetters.for_bill(bill) }
        PublicTestimonyLetterResource.new(entries).serializable_hash
      end
    }
  end

  def self.fetch_organization_positions(bill, cache)
    cache.fetch(bill.object_id) do
      cache[bill.object_id] =
        bill.active_organization_bill_positions
          .includes(organization: {icon_attachment: :blob})
          .map { |position| BillPageOrganizationBillPositionResource.new(position).serializable_hash }
    end
  end

  private

  def organization_positions_cache
    @organization_positions_cache ||= {}
  end

  def browsable_letters_cache
    @browsable_letters_cache ||= {}
  end
end
