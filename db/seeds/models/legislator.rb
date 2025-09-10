# typed: true

# frozen_string_literal: true

require_relative "../seed_preparers/legislators/congress_dot_gov"
require_relative "../seed_preparers/legislators/open_states"
require_relative "../seed_preparers/legislators/sway"

# Creates Legislators in Sway only if they do not exist
class SeedLegislator
    extend T::Sig

    class MissingRegionCode < StandardError
    end

    class NonStateRegionCode < StandardError
    end

    ###################################
    # Class Methods
    ###################################

    sig { params(sway_locale: SwayLocale).returns(T::Array[T::Hash[String, String]]) }
    def self.read_legislators(sway_locale)
        # All Congressional ones are active
        T.let(
            JSON.parse(File.read("storage/seeds/data/#{sway_locale.reversed_name.tr("-", "/")}/legislators.json")),
            T::Array[T::Hash[String, String]],
        )
    end

    sig { params(sway_locales: T::Array[SwayLocale]).void }
    def self.run(sway_locales)
        is_internet_connected =
            begin
                Rails.logger.info("Check is connected to the internet")
                T.unsafe(Faraday).new("https://example.com", 
request: { timeout: 1, read_timeout: 1, open_timeout: 1 }).get
                true
            rescue Faraday::ConnectionFailed
                false
            end

        Rails.logger.info("Is connected to the internet? #{is_internet_connected}")

        sway_locales.each do |sway_locale|
            Rails.logger.info("Seeding Legislators for - #{sway_locale.name}")
            T
                .let(read_legislators(sway_locale), T::Array[T::Hash[String, String]])
                .each do |j|
                    seed_legislator = SeedLegislator.new(j, sway_locale, is_internet_connected)
                    seed_legislator.seed if seed_legislator.present? && seed_legislator.prepared.present?
                end
        end
    end

    sig { params(region_code: T.nilable(String), district: Integer).returns(T.nilable(String)) }
    def self.district_name(region_code, district)
        return nil if region_code.blank?
        "#{region_code}#{district}"
    end

    ###################################
    # Instance Methods
    ###################################

    attr_reader :prepared, :sway_locale

    sig { params(j: T::Hash[String, String], sway_locale: SwayLocale, is_internet_connected: T::Boolean).void }
    def initialize(j, sway_locale, is_internet_connected = true)
        @sway_locale = sway_locale

        @prepared =
            if sway_locale.congress?
                SeedPreparers::Legislators::CongressDotGov.new(j, sway_locale, is_internet_connected)
            elsif sway_locale.regional?
                SeedPreparers::Legislators::OpenStates.new(j, sway_locale, is_internet_connected)
            else
                SeedPreparers::Legislators::Sway.new(j, sway_locale, is_internet_connected)
            end
    end

    sig { returns(T.nilable(Legislator)) }
    def seed
        legislator
    end

    sig { returns(T.nilable(Legislator)) }
    def legislator
        return nil if prepared.json.nil?

        Rails.logger.info("Seeding #{sway_locale.city.titleize} Legislator external_id: #{prepared.external_id}")

        l =
            Legislator.find_or_initialize_by(
                external_id: prepared.external_id,
                first_name: prepared.first_name,
                last_name: prepared.last_name,
            )

        l.district = prepared.district
        l.title = prepared.title
        l.active = prepared.active
        l.party = prepared.party
        l.photo_url = prepared.photo_url
        l.phone = prepared.phone
        l.email = prepared.email
        l.twitter = prepared.twitter
        l.link = prepared.link

        l.save!
        l
    end
end
