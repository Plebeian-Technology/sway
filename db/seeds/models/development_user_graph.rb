# frozen_string_literal: true

require "securerandom"
require "zlib"

class SeedDevelopmentUserGraph
  USER_COUNT = 200
  BALTIMORE_LOCALE_NAME = "baltimore-maryland-united_states"
  MAX_BILLS = 10
  EMAIL_DOMAIN = "dev-baltimore.sway.vote"
  # @lat: [[personal-detail-encryption#Finding the seeded development users]]
  SEEDED_USER_PROBE_LIMIT = 999
  BASE_LATITUDE = 39.2904
  BASE_LONGITUDE = -76.6122

  FIRST_NAMES = %w[
    Avery
    Jordan
    Taylor
    Morgan
    Riley
    Cameron
    Quinn
    Parker
    Skyler
    Reese
    Rowan
    Jamie
    Kendall
    Emerson
    Hayden
    Blake
    Logan
    Sutton
    Finley
    Sawyer
  ].freeze

  LAST_NAMES = %w[
    Johnson
    Smith
    Brown
    Davis
    Wilson
    Moore
    Taylor
    Anderson
    Thomas
    Jackson
    White
    Harris
    Martin
    Thompson
    Garcia
    Martinez
    Robinson
    Clark
    Lewis
    Walker
  ].freeze

  STREET_NAMES = [
    "North Avenue",
    "Charles Street",
    "Greenmount Avenue",
    "Eastern Avenue",
    "Pratt Street",
    "Lombard Street",
    "Monument Street",
    "Fayette Street",
    "Belair Road",
    "Harford Road",
    "Liberty Heights Avenue",
    "Edmondson Avenue"
  ].freeze

  POSTAL_CODES = %w[
    21201
    21202
    21205
    21206
    21210
    21211
    21212
    21213
    21217
    21218
    21224
    21229
    21230
    21231
  ].freeze

  class << self
    def run(sway_locales, user_count: USER_COUNT, vote_seed: nil)
      return unless enabled?

      sway_locale =
        Array(sway_locales).find { |locale| locale.name == BALTIMORE_LOCALE_NAME }
      return if sway_locale.nil?
      return unless sway_locale.bills.exists?

      new(sway_locale, user_count: user_count, vote_seed: vote_seed).run
    end

    # @lat: [[personal-detail-encryption#Finding the seeded development users]]
    def seeded_users
      User.where(email: seeded_user_emails)
    end

    def seeded_user_emails
      (0...SEEDED_USER_PROBE_LIMIT).map { |index| seeded_user_email(index) }
    end

    def seeded_user_email(index)
      format("dev-baltimore-user-%03d@%s", index + 1, EMAIL_DOMAIN)
    end

    def enabled?
      Rails.env.development? && !preview_database?
    end

    private

    def preview_database?
      ENV.fetch("SWAY_DATABASE_NAME", "").include?("preview.sqlite3")
    end
  end

  def initialize(sway_locale, user_count:, vote_seed:)
    @sway_locale = sway_locale
    @user_count = user_count
    @vote_seed = vote_seed || default_vote_seed

    @created_users = 0
    @created_addresses = 0
    @created_user_votes = 0
    @created_legislator_votes = 0
  end

  def run
    return if bills.empty?
    return if seedable_districts.empty?
    return if seedable_legislators.empty?

    seed_legislator_votes
    purge_seeded_user_votes!

    user_indexes.each do |index|
      seed_user_graph_for(index)
    end

    refresh_scores!

    summary = {
      users: user_indexes.length,
      created_users: @created_users,
      created_addresses: @created_addresses,
      created_legislator_votes: @created_legislator_votes,
      created_user_votes: @created_user_votes
    }

    Rails.logger.info("SeedDevelopmentUserGraph: #{summary}")
    summary
  end

  private

  attr_reader :sway_locale, :user_count

  def bills
    @bills ||=
      Bill
        .where(sway_locale: sway_locale)
        .order(introduced_date_time_utc: :desc, id: :asc)
        .limit(MAX_BILLS)
        .to_a
  end

  def all_locale_legislators
    @all_locale_legislators ||=
      Legislator
        .joins(:district)
        .includes(:district)
        .where(districts: {sway_locale_id: sway_locale.id})
        .order(Arel.sql("districts.name ASC, legislators.last_name ASC, legislators.first_name ASC"))
        .to_a
  end

  def locale_legislators
    @locale_legislators ||= all_locale_legislators.reject { |legislator| legislator.active_term&.title == "Mayor" }
  end

  def seedable_districts
    @seedable_districts ||=
      begin
        non_at_large =
          locale_legislators.map(&:district).uniq(&:id).reject do |district|
            district.number.zero?
          end
        non_at_large.presence || locale_legislators.map(&:district).uniq(&:id)
      end
  end

  def shared_legislators
    @shared_legislators ||=
      begin
        council_president =
          locale_legislators.find do |legislator|
            legislator.active_term&.district&.number&.zero? &&
              legislator.active_term&.title == "Council President"
          end

        [council_president].compact
      end
  end

  def district_legislators
    @district_legislators ||=
      locale_legislators.group_by { |legislator| legislator.active_term&.district_id }
  end

  def seedable_legislators
    @seedable_legislators ||=
      begin
        preferred_ids =
          seedable_districts.flat_map do |district|
            district_legislators.fetch(district.id, []).map(&:id)
          end + shared_legislators.map(&:id)

        locale_legislators.select { |legislator| preferred_ids.include?(legislator.id) }
      end
  end

  def seed_legislator_votes
    existing_pairs =
      LegislatorVote
        .where(bill_id: bills.map(&:id), legislator_id: all_locale_legislators.map(&:id))
        .pluck(:bill_id, :legislator_id)
        .to_h { |bill_id, legislator_id| [[bill_id, legislator_id], true] }

    has_term_id_on_votes = LegislatorVote.column_names.include?("legislator_term_id")
    rows = []

    bills.each_with_index do |bill, bill_index|
      all_locale_legislators.each_with_index do |legislator, legislator_index|
        next if existing_pairs[[bill.id, legislator.id]]

        term = resolve_legislator_term(bill, legislator)
        next if term.nil?

        row = {
          bill_id: bill.id,
          legislator_id: legislator.id,
          support: support_for_legislator_vote(legislator, bill_index, legislator_index),
          source: "manual"
        }.merge(timestamps)
        # @lat: [[seeded-development-users#Seeded legislator votes retain their resolved term]]
        row[:legislator_term_id] = term.id if has_term_id_on_votes
        rows << row
      end
    end

    return if rows.empty?

    LegislatorVote.insert_all!(rows)
    @created_legislator_votes += rows.length
  end

  def resolve_legislator_term(bill, legislator)
    anchor = bill.house_vote_date_time_utc || bill.senate_vote_date_time_utc || bill.introduced_date_time_utc
    (LegislatorTerm.covering(anchor, legislator: legislator) if anchor && LegislatorTerm.respond_to?(:covering)) ||
      legislator.active_term ||
      legislator.terms.order(term_start_year: :desc).first
  end

  def seed_user_graph_for(index)
    user = upsert_user(index)
    address = upsert_address(index)
    assign_address(user, address)

    district = seedable_districts[index % seedable_districts.length]
    sync_user_legislators(user, assigned_legislators_for(district))
    # @lat: [[seeded-development-users#Graph users complete after assigning representatives]]
    if user.registered? && (user.registration_status != "completed" || !user.is_registration_complete)
      user.complete!
    end

    rows = []

    bills.each_with_index do |bill, bill_index|
      next unless should_seed_vote_for?(index, bill, bill_index, district)

      rows << {
        user_id: user.id,
        bill_id: bill.id,
        support: support_for_user_vote(index, bill, bill_index, district)
      }.merge(timestamps)
    end

    return if rows.empty?

    UserVote.insert_all!(rows)
    @created_user_votes += rows.length
  end

  def purge_seeded_user_votes!
    UserVote.where(user_id: seeded_users_relation.select(:id), bill_id: bills.map(&:id)).delete_all
  end

  def upsert_user(index)
    user = User.find_or_initialize_by(email: email_for(index))
    @created_users += 1 if user.new_record?

    user.phone = phone_for(index)
    user.full_name = full_name_for(index)
    user.save! if user.new_record? || user.changed?

    seed_profile = {
      is_email_verified: true,
      is_phone_verified: true,
      is_registered_to_vote: true,
      sms_notifications_enabled: index.even?
    }

    current_profile = user.attributes.symbolize_keys.slice(*seed_profile.keys)
    user.update_columns(seed_profile) if current_profile != seed_profile
    user.reload
  end

  def upsert_address(index)
    street = "#{1100 + index} #{STREET_NAMES[index % STREET_NAMES.length]}"
    postal_code = POSTAL_CODES[index % POSTAL_CODES.length]
    latitude = BASE_LATITUDE + ((index % 20) * 0.0025)
    longitude = BASE_LONGITUDE - ((index / 20) * 0.003)

    # @lat: [[personal-detail-encryption#An encrypted column cannot be a lookup key]]
    normalized_key = Address.normalized_key_for(latitude: latitude, longitude: longitude)
    address = Address.find_by(normalized_key: normalized_key) || Address.new
    @created_addresses += 1 if address.new_record?

    address.assign_attributes(
      street: street,
      city: "Baltimore",
      region_code: "MD",
      postal_code: postal_code,
      country: "US",
      latitude: latitude,
      longitude: longitude,
      normalized_key: normalized_key
    )
    address.save! if address.new_record? || address.changed?
    address
  end

  def assign_address(user, address)
    user_address = UserAddress.find_or_initialize_by(user: user)
    return if user_address.address_id == address.id

    user_address.address = address
    user_address.save!
  end

  def sync_user_legislators(user, assigned_legislators)
    assigned_ids = assigned_legislators.map(&:id)

    user_legislators =
      user
        .user_legislators
        .joins(legislator: :district)
        .where(districts: {sway_locale_id: sway_locale.id})
        .includes(:legislator)
        .to_a

    user_legislators.each do |user_legislator|
      next if assigned_ids.include?(user_legislator.legislator_id)
      next unless user_legislator.active?

      user_legislator.update!(active: false)
    end

    assigned_legislators.each do |legislator|
      user_legislator =
        user_legislators.find { |record| record.legislator_id == legislator.id } ||
        UserLegislator.find_or_initialize_by(user: user, legislator: legislator)

      next unless user_legislator.new_record? || !user_legislator.active?

      user_legislator.active = true
      user_legislator.save!
    end
  end

  def assigned_legislators_for(district)
    legislators = district_legislators.fetch(district.id, [])
    legislators = seedable_legislators.first(1) if legislators.empty?

    (legislators + shared_legislators).uniq(&:id)
  end

  def should_seed_vote_for?(user_index, bill, bill_index, district)
    deterministic_percent("participation", vote_seed, user_index, bill.id) <
      participation_threshold_for(district, bill, bill_index)
  end

  def support_for_legislator_vote(legislator, bill_index, legislator_index)
    support_index =
      (legislator.active_term&.district&.number.to_i + bill_index + legislator_index) % 6

    case support_index
    when 0
      LegislatorVote::Support::ABSTAIN
    when 1, 2
      LegislatorVote::Support::AGAINST
    else
      LegislatorVote::Support::FOR
    end
  end

  def support_for_user_vote(user_index, bill, bill_index, district)
    threshold = support_threshold_for(district, bill, bill_index)

    if deterministic_percent("support", vote_seed, user_index, district.id, bill_index) <
        threshold
      LegislatorVote::Support::FOR
    else
      LegislatorVote::Support::AGAINST
    end
  end

  def email_for(index)
    self.class.seeded_user_email(index)
  end

  # @lat: [[seeded-development-users#Seeded users carry numbers no carrier will route]]
  def phone_for(index)
    format("%010d", 333_000_0000 + index + 1)
  end

  def full_name_for(index)
    first_name = FIRST_NAMES[index % FIRST_NAMES.length]
    last_name = LAST_NAMES[(index / FIRST_NAMES.length) % LAST_NAMES.length]
    "#{first_name} #{last_name}"
  end

  def refresh_scores!
    refresh_bill_scores!
    refresh_bill_score_districts!
    refresh_legislator_district_scores!
    refresh_user_legislator_scores!
  end

  def refresh_bill_scores!
    counts =
      UserVote
        .where(bill_id: bills.map(&:id))
        .group(:bill_id, :support)
        .count

    bills.each do |bill|
      bill_score = BillScore.find_or_create_by!(bill: bill)
      update_record_columns(
        bill_score,
        for: counts.fetch([bill.id, LegislatorVote::Support::FOR], 0),
        against: counts.fetch([bill.id, LegislatorVote::Support::AGAINST], 0)
      )
    end
  end

  def refresh_bill_score_districts!
    district_user_ids = user_ids_by_district_id
    user_votes_by_bill_id = user_votes.group_by(&:bill_id)

    bills.each do |bill|
      bill_score = BillScore.find_or_create_by!(bill: bill)
      bill_votes = user_votes_by_bill_id.fetch(bill.id, [])

      seedable_districts.each do |district|
        district_votes =
          bill_votes.select do |user_vote|
            district_user_ids.fetch(district.id, {}).key?(user_vote.user_id)
          end

        bill_score_district =
          BillScoreDistrict.find_or_create_by!(bill_score: bill_score, district: district)

        update_record_columns(
          bill_score_district,
          for: district_votes.count(&:for?),
          against: district_votes.count(&:against?)
        )
      end
    end
  end

  def refresh_legislator_district_scores!
    active_user_ids_by_legislator_id =
      locale_user_legislators
        .select(&:active?)
        .group_by(&:legislator_id)
        .transform_values do |user_legislators|
          user_legislators.each_with_object({}) do |user_legislator, memo|
            memo[user_legislator.user_id] = true
          end
        end

    all_locale_legislators.each do |legislator|
      # @lat: [[seeded-development-users#Score refresh follows current legislator terms]]
      legislator_score = LegislatorDistrictScore.find_or_create_by!(legislator_term: legislator.active_term)
      related_user_votes =
        user_votes.select do |user_vote|
          active_user_ids_by_legislator_id.fetch(legislator.id, {}).key?(user_vote.user_id)
        end

      update_record_columns(
        legislator_score,
        comparable_counts(related_user_votes, legislator_votes_by_legislator_id.fetch(legislator.id, {}))
      )
    end
  end

  # @lat: [[seeded-development-users#Score refresh follows current legislator terms]]
  def refresh_user_legislator_scores!
    locale_user_legislators.each do |user_legislator|
      legislator_term = user_legislator.legislator.active_term
      next if legislator_term.nil?

      user_legislator_term_score =
        UserLegislatorTermScore.find_or_create_by!(user_legislator: user_legislator, legislator_term: legislator_term)

      counts =
        if user_legislator.active?
          comparable_counts(
            user_votes_by_user_id.fetch(user_legislator.user_id, []),
            legislator_votes_by_legislator_id.fetch(user_legislator.legislator_id, {})
          )
        else
          zero_counts
        end

      update_record_columns(user_legislator_term_score, counts)
    end
  end

  def user_votes
    @user_votes ||= UserVote.where(bill_id: bills.map(&:id)).to_a
  end

  def user_votes_by_user_id
    @user_votes_by_user_id ||= user_votes.group_by(&:user_id)
  end

  def legislator_votes_by_legislator_id
    @legislator_votes_by_legislator_id ||=
      LegislatorVote
        .where(bill_id: bills.map(&:id), legislator_id: all_locale_legislators.map(&:id))
        .to_a
        .group_by(&:legislator_id)
        .transform_values { |votes| votes.index_by(&:bill_id) }
  end

  def locale_user_legislators
    @locale_user_legislators ||=
      UserLegislator
        .joins(legislator: :district)
        .where(districts: {sway_locale_id: sway_locale.id})
        .to_a
  end

  # Returns {district_id => {user_id => true}}.
  # @lat: [[seeded-development-users#Synthetic users resolve district coverage through active representatives]]
  def user_ids_by_district_id
    @user_ids_by_district_id ||=
      UserLegislator
        .where(active: true)
        .joins(legislator: :district)
        .where(districts: {sway_locale_id: sway_locale.id})
        .pluck("districts.id", :user_id)
        .group_by(&:first)
        .transform_values do |rows|
          rows.each_with_object({}) do |(_district_id, user_id), memo|
            memo[user_id] = true
          end
        end
  end

  def comparable_counts(user_votes, legislator_votes_by_bill_id)
    user_votes.each_with_object(zero_counts.dup) do |user_vote, memo|
      legislator_vote = legislator_votes_by_bill_id[user_vote.bill_id]

      if legislator_vote.nil?
        memo[:count_no_legislator_vote] += 1
      elsif user_vote.support == legislator_vote.support
        memo[:count_agreed] += 1
      else
        memo[:count_disagreed] += 1
        memo[:count_legislator_abstained] += 1 if legislator_vote.abstain?
      end
    end
  end

  def zero_counts
    {
      count_agreed: 0,
      count_disagreed: 0,
      count_legislator_abstained: 0,
      count_no_legislator_vote: 0
    }
  end

  def timestamps
    now = Time.current
    {created_at: now, updated_at: now}
  end

  def participation_threshold_for(district, bill, bill_index)
    52 + deterministic_mod(31, "participation-threshold", district.id, bill.id, bill_index)
  end

  def support_threshold_for(district, bill, bill_index)
    34 + deterministic_mod(49, "support-threshold", district.id, bill.id, bill_index)
  end

  def deterministic_percent(*parts)
    deterministic_mod(100, *parts)
  end

  def deterministic_mod(modulus, *parts)
    Zlib.crc32(parts.join(":")) % modulus
  end

  def seeded_users_relation
    self.class.seeded_users
  end

  def user_indexes
    @user_indexes ||= (0...[user_count, existing_seeded_user_count].max).to_a
  end

  def existing_seeded_user_count
    seeded_users_relation.count
  end

  def default_vote_seed
    SecureRandom.hex(8)
  end

  attr_reader :vote_seed

  def update_record_columns(record, attributes)
    record.update_columns(attributes.merge(updated_at: Time.current))
  end
end
