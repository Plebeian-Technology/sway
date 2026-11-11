# == Schema Information
#
# Table name: sway_locales
# Database name: primary
#
#  id                           :integer          not null, primary key
#  city                         :string           not null
#  country                      :string           default("United States"), not null
#  icon_url                     :string
#  last_seeded_at               :datetime
#  latest_election_year         :integer          default(2024), not null
#  legislators_cache_fetched_at :datetime
#  region_name                  :string           not null
#  sample_latitude              :float
#  sample_longitude             :float
#  sample_postal_code           :string
#  sample_street                :string
#  time_zone                    :string
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#
# Indexes
#
#  index_sway_locales_on_city_and_region_name_and_country  (city,region_name,country) UNIQUE
#
require Rails.root.join("db", "seeds", "models", "sway_locale")

FactoryBot.define do
  # @lat: [[jurisdiction-rules#A test fixture names a jurisdiction in full or not at all]]
  seeded_locales = SwayLocale::DocumentReader.all.map do |doc|
    {"city" => doc.city, "region" => doc.region, "country" => doc.country}
  end

  factory :sway_locale do
    transient do
      sequence(:seeded_locale_index) { |n| n % seeded_locales.length }

      # nil means "not named". See the note above.
      city { nil }
      state { nil }
      region_name { nil }
      country { nil }

      # @lat: [[identity-and-access#The stand-in account borrows a jurisdiction's sample address]]
      # nil takes the jurisdiction's seeded sample address, when it has one.
      sample_street { nil }
      sample_postal_code { nil }
      sample_latitude { nil }
      sample_longitude { nil }
    end

    time_zone { "Etc/UTC" }
    icon_url { "logo.svg" }

    # @lat: [[sway-locale-factory-design#Concurrent creates: a mutex and bounded retry]]
    sway_locale_factory_mutex = Mutex.new

    # @lat: [[sway-locale-factory-design#Normalization and reuse: a locale belongs to whoever made it first]]
    to_create do |instance|
      if instance.new_record?
        instance.save!
      else
        instance.reload
      end
    end

    # The three jurisdictions Sway really seeds, so a spec that needs a
    # particular one asks for it by name rather than by rotation position.
    trait :baltimore do
      city { "baltimore" }
      region_name { "maryland" }
      state { "maryland" }
      country { "united_states" }
    end

    trait :maryland do
      city { "maryland" }
      region_name { "maryland" }
      state { "maryland" }
      country { "united_states" }
    end

    trait :congress do
      city { "congress" }
      region_name { "congress" }
      state { "congress" }
      country { "united_states" }
    end

    initialize_with do
      effective_region = region_name || state
      named = {city: city, state: effective_region, country: country}.compact

      if named.any? && named.size < 3
        raise ArgumentError,
          "create(:sway_locale, #{named.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")}) names " \
          "part of a jurisdiction. The rest would come from a rotation position, which builds a " \
          "place that does not exist — and only in a full run, once earlier specs have moved the " \
          "rotation. Name all three (city:, state:, country:), or use a trait: " \
          ":baltimore, :maryland, :congress."
      end

      rotating = seeded_locales.fetch(seeded_locale_index)
      attrs = SwayLocale.normalize_attributes(
        city: named.fetch(:city) { rotating.fetch("city") },
        region_name: effective_region || rotating.fetch("region"),
        country: named.fetch(:country) { rotating.fetch("country") }
      )

      doc = SwayLocale::DocumentReader.find("#{attrs[:city]}-#{attrs[:state]}-#{attrs[:country]}")
      seeded_sample = if doc&.sample_address&.present?
        {
          sample_street: doc.sample_street,
          sample_postal_code: doc.sample_postal_code,
          sample_latitude: doc.sample_latitude,
          sample_longitude: doc.sample_longitude
        }
      else
        {}
      end #: Hash[Symbol, untyped]

      sample = seeded_sample.merge(
        {
          sample_street: sample_street,
          sample_postal_code: sample_postal_code,
          sample_latitude: sample_latitude,
          sample_longitude: sample_longitude
        }.compact
      )

      sway_locale_factory_mutex.synchronize do
        found = SwayLocale.find_by(**attrs)
        if found
          found.update!(**sample) if sample.any?
          break found
        end

        attempts = 0
        committed = nil #: SwayLocale?
        loop do
          attempts += 1
          begin
            committed = SwayLocale.create!(
              **attrs,
              **sample,
              time_zone: time_zone,
              icon_url: icon_url
            )
            break
          rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordNotFound
            committed = SwayLocale.find_by(**attrs)
            break if committed
            raise if attempts >= 5
            sleep 0.1
          end
        end
        committed
      end
    end
  end
end
