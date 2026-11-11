# frozen_string_literal: true

# @lat: [[congress-roster-service-design#Why it reads terms.item as stretches rather than trusting a stored term's own title]]
class CongressRoster
  ROSTER_PATH = "db/seeds/data/united_states/congress/congress/legislators.json"

  def initialize(path = Rails.root.join(ROSTER_PATH))
    @path = path
  end

  # @lat: [[congress-roster-service-design#Why CongressRoster reads stretches of service, not terms]]
  def title_in(external_id, year)
    stretch = stretch_in(external_id, year)
    return nil if stretch.nil?

    CongressChamber.title_for(stretch[:chamber])
  end

  # @lat: [[congress-roster-service-design#Why CongressRoster reads stretches of service, not terms]]
  def service_ended_in(external_id, year)
    stretch_in(external_id, year)&.fetch(:end)
  end

  private

  attr_reader :path

  # @lat: [[congress-roster-service-design#Why it reads terms.item as stretches rather than trusting a stored term's own title]]
  def stretch_in(external_id, year)
    stretches = by_external_id[external_id]
    return nil if stretches.blank?

    stretches.find { |stretch| stretch[:start] <= year && (stretch[:end].nil? || year < stretch[:end]) } ||
      stretches.select { |stretch| stretch[:start] <= year }.max_by { |stretch| stretch[:start] }
  end

  def by_external_id
    @by_external_id ||= JSON.parse(File.read(path)).each_with_object({}) do |entry, roster|
      stretches = stretches_from(entry)
      roster[entry["bioguideId"].to_s] = stretches if stretches.any?
    end
  end

  # @lat: [[congress-roster-service-design#Why it reads terms.item as stretches rather than trusting a stored term's own title]]
  def stretches_from(entry)
    items = entry.dig("terms", "item")
    return [] unless items.is_a?(Array)

    items.filter_map do |item|
      start_year = item["startYear"]&.to_i
      next nil if start_year.nil?

      {start: start_year, end: item["endYear"]&.to_i, chamber: item["chamber"].to_s}
    end
  end
end
