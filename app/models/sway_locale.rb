# frozen_string_literal: true
# typed: true

# == Schema Information
#
# Table name: sway_locales
#
#  id                         :integer          not null, primary key
#  city                       :string           not null
#  country                    :string           default("United States"), not null
#  current_session_start_date :date
#  icon_path                  :string
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
  extend T::Sig

  T::Configuration.inline_type_error_handler = lambda do |error, _opts|
    Rails.logger.error error
  end

  has_many :bills, dependent: :destroy

  # use inverse_of to specify relationship
  # https://stackoverflow.com/a/59222913/6410635
  has_many :districts, inverse_of: :sway_locale, dependent: :destroy

  # NOT WORKING
  # has_many :legislators, through: :districts, inverse_of: :sway_locale

  after_initialize :nameify_country, :nameify_region, :nameify_city

  # scope :find_or_create_by_normalized!, lambda { |**keywords|
  #                                         find_or_create_by!(**normalize_keywords(keywords))
  #                                       }
  scope :default_locale, lambda {
    find_by(city: "congress",
      state: "congress",
      country: "united_states")
  }

  class << self
    extend T::Sig

    sig { params(name: String).returns(String) }
    def format_name(name)
      name.strip.downcase.split(" ").join("_")
    end

    # sorbet kwargs - https://sorbet.org/docs/sigs#rest-parameters
    sig { params(kwargs: String).returns(SwayLocale) }
    def find_or_create_by_normalized!(**kwargs)
      SwayLocale.find_or_create_by!(**SwayLocale.new(kwargs).attributes.compact)
    end
  end

  sig { returns(T::Boolean) }
  def congress?
    city_name == "congress" && region_name == "congress"
  end

  sig { returns(T::Boolean) }
  def region?
    RegionUtil.from_region_name_to_region_code(city_name).present?
  end

  sig { params(active: T.nilable(Boolean)).returns(ActiveRecord::Relation) }
  def legislators(active = true)
    Legislator.joins(:district).where(
      active: active,
      district: {
        sway_locale: self
      }
    )
  end

  sig { returns(String) }
  def name
    "#{city_name}-#{region_name}-#{country_name}"
  end

  sig { returns(String) }
  def reversed_name
    "#{country_name}-#{region_name}-#{city_name}"
  end

  sig { returns(String) }
  def human_name
    name.split("-").map(&:titleize).join(", ").split("_").join(" ")
  end

  sig { returns(String) }
  def region_code
    T.cast(RegionUtil.from_region_name_to_region_code(region_name), String)
  end

  sig { returns(T::Array[Bill]) }
  def bills
    Bill.where(sway_locale: self).order(created_at: :desc).to_a
  end

  sig { returns(T::Boolean) }
  def has_geojson?
    File.exist?(geojson_file_name)
  end

  sig { returns(T.nilable(RGeo::GeoJSON::FeatureCollection)) }
  def load_geojson
    unless has_geojson?
      Rails.logger.info "SwayLocale - #{name} - has no geojson file located at - #{geojson_file_name}"
      return nil
    end

    T.let(RGeo::GeoJSON.decode(File.read(geojson_file_name)), RGeo::GeoJSON::FeatureCollection)
  end

  sig { params(current_user: T.nilable(User)).returns(Jbuilder) }
  def to_builder(current_user)
    Jbuilder.new do |s|
      s.id id
      s.name name
      s.city city
      s.region_name region_name
      s.region_code region_code
      s.country country

      s.time_zone time_zone
      s.icon_path icon_path
      s.current_session_start_date current_session_start_date

      s.districts current_user&.districts(self)&.map { |d| d.to_builder.attributes! } || []
      # icon
      # timezone
    end
  end

  private

  sig { returns(String) }
  def country_name
    SwayLocale.format_name(T.cast(RegionUtil.from_country_code_to_name(country), String))
  end

  sig { returns(String) }
  def region_name
    SwayLocale.format_name(T.cast(RegionUtil.from_region_code_to_region_name(state), String))
  end

  sig { returns(String) }
  def city_name
    SwayLocale.format_name(T.cast(city, String))
  end

  sig { void }
  def nameify_country
    self.country = country_name
  end

  sig { void }
  def nameify_region
    self.state = region_name
  end

  sig { void }
  def nameify_city
    self.city = city_name
  end

  sig { returns(String) }
  def geojson_file_name
    "storage/geojson/#{name}.geojson"
  end
end
