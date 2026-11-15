# frozen_string_literal: true

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

class SwayLocale < ApplicationRecord
  alias_attribute :state, :region_name

  def current_session_start_date
    current_legislative_session&.start_date
  end

  has_many :bills, dependent: :destroy

  has_many :districts, inverse_of: :sway_locale, dependent: :destroy

  has_many :organizations, inverse_of: :sway_locale, dependent: :destroy
  has_many :legislative_sessions, inverse_of: :sway_locale, dependent: :destroy
  has_one :current_legislative_session,
    -> { where(active: true).order(start_date: :desc) },
    class_name: "LegislativeSession",
    inverse_of: :sway_locale
  has_one :llm_bill_summarization_instruction, dependent: :destroy
  has_one_attached :icon

  before_validation :nameify_country, :nameify_region, :nameify_city

  class << self
    def declared
      all.select(&:declared?)
    end

    # @lat: [[locale-name-is-derived#A locale's name is derived, not stored]]
    def find_by_name_parts(name)
      return nil if name.blank?

      city, reg, country = name.split("-")
      SwayLocale.find_by(city:, region_name: reg, country:)
    end

    # @lat: [[locale-name-is-derived#A locale's name is derived, not stored]]
    def resolve_by_computed_name(name)
      all.to_a.detect { |locale| locale.name == name }
    end

    def format_name(name)
      name.strip.downcase.split(" ").join("_")
    end

    # @lat: [[locale-user-counts#How many people have registered in each locale#Why the count matches against existing locale rows]]
    def find_or_create_by_normalized!(**kwargs)
      attributes = normalize_attributes(kwargs)
      SwayLocale.find_or_create_by!(**attributes)
    rescue ActiveRecord::RecordNotUnique
      SwayLocale.find_by(**attributes) || raise
    end

    # @lat: [[locale-name-is-derived#Which attributes the memo is keyed on]]
    def normalize_attributes(attrs)
      normalized = attrs.symbolize_keys
      city = normalized[:city]
      normalized[:city] = format_name(city) if city
      reg = normalized[:region_name] || normalized[:state]
      if reg
        reg_name = RegionUtil.from_region_code_to_region_name(reg)
        formatted = format_name(reg_name) if reg_name
        normalized[:region_name] = formatted if formatted
        normalized[:state] = formatted if formatted
      end
      country = normalized[:country]
      if country
        country_name = RegionUtil.from_country_code_to_name(country)
        normalized[:country] = format_name(country_name) if country_name
      end
      normalized
    end

    def default_locale
      find_by(city: "congress", region_name: "congress", country: "united_states")
    end
  end

  # @lat: [[jurisdiction-rules#Jurisdiction declarations]]
  def term_rules
    TermRulesRegistry.fetch(name)
  end

  # @lat: [[representative-resolution#Locale-wide district]]
  def locale_wide_district_name
    document&.locale_wide_district_name
  end

  # @lat: [[jurisdiction-rules#Declared bill chambers]]
  def jurisdiction_rules
    JurisdictionRulesRegistry.fetch(name)
  end

  def declared?
    JurisdictionRulesRegistry.declared?(name)
  end

  # @lat: [[jurisdiction-rules#Declared bill chambers]]
  def declared_jurisdiction_rules
    current_name = name
    unless defined?(@declared_jurisdiction_rules_name_key) && @declared_jurisdiction_rules_name_key == current_name
      @declared_jurisdiction_rules_name_key = current_name
      @declared_jurisdiction_rules = declared? ? jurisdiction_rules : nil
    end
    @declared_jurisdiction_rules
  end

  # @lat: [[request-locale-selection#One request reuses its locale lookup]]
  def at_large_district
    locale_wide_name = locale_wide_district_name
    if districts.loaded?
      found = districts.find { |d| d.name == locale_wide_name } if locale_wide_name.present?
      return found || districts.find { |d| d.number.zero? }
    end
    return @at_large_district if defined?(@at_large_district)

    @at_large_district =
      (locale_wide_name.present? && districts.find_by(name: locale_wide_name)) ||
      districts.where("NOT (name GLOB '*[1-9]*')").order(:id).first
  end

  def reload(*)
    remove_instance_variable(:@at_large_district) if defined?(@at_large_district)
    remove_instance_variable(:@name_key) if defined?(@name_key)
    remove_instance_variable(:@name) if defined?(@name)
    remove_instance_variable(:@document_name_key) if defined?(@document_name_key)
    remove_instance_variable(:@document) if defined?(@document)
    remove_instance_variable(:@declared_jurisdiction_rules_name_key) if defined?(@declared_jurisdiction_rules_name_key)
    remove_instance_variable(:@declared_jurisdiction_rules) if defined?(@declared_jurisdiction_rules)
    remove_instance_variable(:@geojson) if defined?(@geojson)
    super
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
    !congress? && !regional?
  end

  def tier
    return "congress" if congress?
    return "state" if regional?

    "city"
  end

  # @lat: [[current-legislator-term#Which term a legislator is serving now]]
  def legislators(active = true)
    scope = Legislator.where(sway_locale: self)
    active ? scope.merge(Legislator.serving).distinct : scope
  end

  # @lat: [[locale-name-is-derived#Which attributes the memo is keyed on]]
  def name
    key = [city, state, country] #: [String?, String?, String?]
    unless defined?(@name_key) && @name_key == key
      @name_key = key
      @name = "#{city_name}-#{region_name}-#{country_name}"
    end
    @name
  end
  alias_method :slug, :name

  def generic_portal_urls
    declared_jurisdiction_rules&.generic_portal_urls || []
  end

  # @lat: [[locale-extension#Planned declarative contract]]
  def document
    current_name = name
    unless defined?(@document_name_key) && @document_name_key == current_name
      @document_name_key = current_name
      @document = DocumentReader.find(current_name)
    end
    @document
  end

  def nominatim_viewbox
    return @nominatim_viewbox if defined?(@nominatim_viewbox)

    document&.nominatim_viewbox
  end
  attr_writer :nominatim_viewbox

  def nominatim_bounded
    return @nominatim_bounded if defined?(@nominatim_bounded)

    document&.nominatim_bounded
  end
  attr_writer :nominatim_bounded

  def nominatim_country_codes
    return @nominatim_country_codes if defined?(@nominatim_country_codes)

    document&.nominatim_country_codes
  end
  attr_writer :nominatim_country_codes

  def reversed_name
    "#{country_name}-#{region_name}-#{city_name}"
  end

  def human_name
    name.split("-").map(&:titleize).uniq.join(", ").split("_").join(" ")
  end

  def short_name
    if congress?
      "U.S. Congress"
    elsif regional?
      region_name.titleize
    else
      city_name.titleize
    end
  end

  # @lat: [[locale-name-is-derived#A locale's name is derived, not stored#The picker's options are formatted before they leave the server]]
  def to_select_option
    {
      label: congress? ? "U.S. Congress" : human_name,
      value: id
    }
  end

  def state
    region_name
  end

  def region_code
    RegionUtil.from_region_name_to_region_code(region_name)
  end

  def state_code
    region_code
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
      SwayLogging.info "SwayLocale - #{name} - has no geojson file located at - #{geojson_file_name}"
      return @geojson
    end

    decoded_geojson = RGeo::GeoJSON.decode(File.read(geojson_file_name))
    @geojson = decoded_geojson
  end

  def to_builder
    rules = declared_jurisdiction_rules
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

      # @lat: [[jurisdiction-rules#Declared bill chambers]]
      s.default_bill_chamber rules&.default_bill_chamber

      s.bill_chambers rules&.bill_chambers

      # @lat: [[locale-extension#Lossless district identifier representation]]
      s.districts nil

      s.generic_portal_urls rules&.generic_portal_urls || []

      s.nominatim_viewbox nominatim_viewbox
      s.nominatim_bounded nominatim_bounded
      s.nominatim_country_codes nominatim_country_codes
    end
  end

  def country_name
    SwayLocale.format_name(RegionUtil.from_country_code_to_name(country))
  end

  def region_name
    val = read_attribute(:region_name)
    return val if val.blank?

    SwayLocale.format_name(RegionUtil.from_region_code_to_region_name(val))
  end

  def city_name
    SwayLocale.format_name(city)
  end

  # @lat: [[locale-extension#Legislative session schema and validations]]
  def legislative_session_for_date(date)
    return nil if date.blank?

    target_date =
      if date.is_a?(String)
        Date.parse(date)
      elsif date.respond_to?(:to_date)
        date.to_date
      else
        date
      end
    legislative_sessions.containing_date(target_date).order(start_date: :desc).first
  rescue ArgumentError
    nil
  end

  private

  def nameify_country
    self.country = country_name
  end

  def nameify_region
    self.region_name = region_name
  end

  def nameify_city
    self.city = city_name
  end

  def geojson_file_name
    "storage/geojson/#{name}.geojson"
  end
end
