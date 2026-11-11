# frozen_string_literal: true

require_relative "../seedable"

class SeedSwayLocale
  include Seedable

  # @lat: [[identity-and-access#The stand-in account borrows a jurisdiction's sample address]]
  # Retained for backwards compatibility with any legacy test references.
  SAMPLE_ADDRESSES = {
    "baltimore-maryland-united_states" => {
      sample_street: "100 N Holliday St",
      sample_postal_code: "21202",
      sample_latitude: 39.29105,
      sample_longitude: -76.61069
    }
  }.freeze

  # Returns every locale, including ones seed_or_skip? left alone.
  # @lat: [[seed-sway-locale-skipped-locales#Why SeedSwayLocale.run returns skipped locales too]]
  def self.run(force: false)
    SwayLocale::DocumentReader.all.map { |doc| SeedSwayLocale.new.seed(doc, force: force) }
  end

  def self.read_locales
    SwayLocale::DocumentReader.all.map(&:to_sway_locale_attributes)
  end

  def seed(doc_or_data, force: false)
    doc = if doc_or_data.respond_to?(:sync_legislative_sessions!)
      doc_or_data
    else
      name = doc_or_data["name"] || doc_or_data[:name]
      SwayLocale::DocumentReader.find(name) if name
    end

    data = if doc_or_data.respond_to?(:to_sway_locale_attributes)
      doc_or_data.to_sway_locale_attributes.transform_keys(&:to_s)
    else
      doc_or_data.transform_keys(&:to_s)
    end

    s =
      SwayLocale.find_or_initialize_by(
        city: data.fetch("city"),
        state: data.fetch("region") { data.fetch("state") },
        country: data.fetch("country")
      )
    doc ||= SwayLocale::DocumentReader.find(s.name)
    if seed_or_skip?(s, force: force)
      Rails.logger.info("SeedSwayLocale: skipping #{s.city}/#{s.state} — edited out-of-band since last seed")
      doc&.sync_legislative_sessions!(s)
      return s
    end
    s.time_zone = data.fetch("time_zone", "America/New_York")
    s.icon_url =
      data.fetch("icon_url", data.fetch("icon_path", "logo.svg"))

    sample = if data["sample_street"].present?
      {
        sample_street: data["sample_street"],
        sample_postal_code: data["sample_postal_code"],
        sample_latitude: data["sample_latitude"],
        sample_longitude: data["sample_longitude"]
      }
    elsif data["sample_address"].is_a?(Hash) && data["sample_address"].present?
      addr = data["sample_address"]
      {
        sample_street: addr["street"] || addr[:street],
        sample_postal_code: addr["postal_code"] || addr[:postal_code],
        sample_latitude: (addr["latitude"] || addr[:latitude])&.to_f,
        sample_longitude: (addr["longitude"] || addr[:longitude])&.to_f
      }
    else
      SAMPLE_ADDRESSES.fetch(data["name"], {})
    end

    s.sample_street = sample[:sample_street]
    s.sample_postal_code = sample[:sample_postal_code]
    s.sample_latitude = sample[:sample_latitude]
    s.sample_longitude = sample[:sample_longitude]
    s.save!
    doc&.sync_legislative_sessions!(s)
    stamp_seeded_at!(s)
    s
  end
end
