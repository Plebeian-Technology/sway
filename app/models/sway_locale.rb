# frozen_string_literal: true

# == Schema Information
#
# Table name: sway_locales
# Database name: primary
#
#  id                         :integer          not null, primary key
#  city                       :string           not null
#  country                    :string           default("United States"), not null
#  current_session_start_date :date
#  icon_url                   :string
#  latest_election_year       :integer          default(2024), not null
#  state                      :string           not null
#  time_zone                  :string
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#
# Indexes
#
#  index_sway_locales_on_city_and_state_and_country  (city,state,country) UNIQUE
#

class SwayLocale < ApplicationRecord
  has_many :bills, dependent: :destroy

  # use inverse_of to specify relationship
  # https://stackoverflow.com/a/59222913/6410635
  has_many :districts, inverse_of: :sway_locale, dependent: :destroy

  has_many :organizations, inverse_of: :sway_locale, dependent: :destroy
  has_one_attached :icon

  after_commit :enqueue_icon_mirroring, if: :saved_change_to_icon_url?

  # NOT WORKING
  # has_many :legislators, through: :districts, inverse_of: :sway_locale

  after_initialize :nameify_country, :nameify_region, :nameify_city

  # scope :find_or_create_by_normalized!, lambda { |**keywords|
  #                                         find_or_create_by!(**normalize_keywords(keywords))
  #                                       }

  class << self
    def find_by_name(name)
      return nil if name.blank?

      city, state, country = name.split("-")
      SwayLocale.find_by(city:, state:, country:)
    end

    def format_name(name)
      name.strip.downcase.split(" ").join("_")
    end

    # sorbet kwargs - https://sorbet.org/docs/sigs#rest-parameters
    def find_or_create_by_normalized!(**kwargs)
      SwayLocale.find_or_create_by!(**SwayLocale.new(kwargs).attributes.compact)
    end

    def default_locale
      find_by(city: "congress", state: "congress", country: "united_states")
    end
  end

  def at_large_district
    districts.find { |d| d.number.zero? }
  end

  def congress?
    city_name == "congress" && region_name == "congress"
  end

  def regional?
    return false if congress?

    RegionUtil.from_region_name_to_region_code(city_name).present? &&
      RegionUtil.from_region_name_to_region_code(city_name) ==
        RegionUtil.from_region_name_to_region_code(region_name)
  end

  def local?
    @local ||= !congress? && !regional?
  end

  def legislators(active = true)
    Legislator
      .joins(:district)
      .includes(:district)
      .where(active: active, district: { sway_locale: self })
  end

  def name
    "#{city_name}-#{region_name}-#{country_name}"
  end

  def reversed_name
    "#{country_name}-#{region_name}-#{city_name}"
  end

  def human_name
    name.split("-").map(&:titleize).join(", ").split("_").join(" ")
  end

  def region_code
    RegionUtil.from_region_name_to_region_code(region_name)
  end

  def bills
    super.order(created_at: :desc)
  end

  def has_geojson?
    File.exist?(geojson_file_name)
  end

  def load_geojson
    return @geojson if defined?(@geojson)

    @geojson = nil

    unless has_geojson?
      Rails.logger.info "SwayLocale - #{name} - has no geojson file located at - #{geojson_file_name}"
      return @geojson
    end

    decoded_geojson = RGeo::GeoJSON.decode(File.read(geojson_file_name))
    @geojson = decoded_geojson
  end

  def to_builder
    Jbuilder.new do |s|
      s.id id
      s.name name
      s.city city
      s.region_name region_name
      s.region_code region_code
      s.country country

      s.time_zone time_zone
      s.icon_url icon_url
      s.current_session_start_date current_session_start_date

      # s.districts districts.map(&:to_sway_json)
      s.districts nil
      # icon
      # timezone
    end
  end

  def country_name
    SwayLocale.format_name(RegionUtil.from_country_code_to_name(country))
  end

  def region_name
    SwayLocale.format_name(RegionUtil.from_region_code_to_region_name(state))
  end

  def city_name
    SwayLocale.format_name(city)
  end

  private

  def enqueue_icon_mirroring
    return if id.blank?
    return if internal_asset_url?(icon_url)

    MirrorExternalAssetJob.perform_later(
      record_class_name: self.class.name,
      record_id: id,
      attachment_name: "icon",
      url_column: "icon_url",
    )
  end

  def internal_asset_url?(url)
    return true if url.blank?

    uri = URI.parse(url)
    return false unless uri.is_a?(URI::HTTP)

    host = uri.host.to_s.downcase
    host.ends_with?("sway.vote") ||
      (
        host == "storage.googleapis.com" &&
          uri.path.to_s.start_with?("/sway-assets/")
      )
  rescue URI::InvalidURIError
    false
  end

  def nameify_country
    self.country = country_name
  end

  def nameify_region
    self.state = region_name
  end

  def nameify_city
    self.city = city_name
  end

  def geojson_file_name
    "storage/geojson/#{name}.geojson"
  end
end
