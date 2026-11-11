# frozen_string_literal: true

# @lat: [[legislator-identity-value-design#What production_legislator_identity_spec.rb checks]]
class LegislatorIdentity
  BIOGUIDE = "bioguide"

  OPENSTATES = "openstates"

  SEAT_AND_NAME = "seat_and_name"

  CURATED_PERSON = "curated_person"

  # @lat: [[legislator-identity-value-design#Why a seat may not contain the separator]]
  SEPARATOR = "|"

  attr_reader :source, :value

  class << self
    # @lat: [[legislator-identity-value-design#Why seat_and_name returns nil on a blank published name]]
    def seat_and_name(seat:, first_name:, last_name:)
      key = name_key(first_name, last_name)
      return nil if key.nil? || seat.blank?

      # @lat: [[legislator-identity-value-design#What production_legislator_identity_spec.rb checks]]
      if seat.to_s.include?(SEPARATOR)
        raise ArgumentError,
          "A seat may not contain #{SEPARATOR.inspect} (got #{seat.inspect}). It separates the " \
          "seat from the name, so a seat carrying one makes the pair unreadable."
      end

      new(source: SEAT_AND_NAME, value: "#{seat}#{SEPARATOR}#{key}")
    end

    # @lat: [[legislator-identity-value-design#Why seat_from exists as its own method]]
    def seat_from(value)
      seat, name_key = value.to_s.split(SEPARATOR, 2)
      return nil if name_key.blank?

      seat.presence
    end

    def from_published_id(source, published_id)
      return nil if published_id.blank?

      new(source: source, value: published_id.to_s)
    end

    # @lat: [[legislator-identity-value-design#Why name_key folds accents before collapsing punctuation]]
    def name_key(first_name, last_name)
      folded =
        "#{first_name} #{last_name}"
          .unicode_normalize(:nfkd)
          .gsub(/\p{Mn}/, "")
          .downcase
          .gsub(/[^a-z0-9]+/, "-")
          .delete_prefix("-")
          .delete_suffix("-")

      folded.presence
    end
  end

  def initialize(source:, value:)
    if source.blank? || value.blank?
      raise ArgumentError,
        "A legislator identity needs both a source and a value " \
        "(got source: #{source.inspect}, value: #{value.inspect})"
    end

    @source = source.to_s
    @value = value.to_s
  end

  def ==(other)
    other.is_a?(LegislatorIdentity) && other.source == source && other.value == value
  end
  alias_method :eql?, :==

  def hash
    [source, value].hash
  end

  def to_s
    "#{source}:#{value}"
  end
end
