# typed: true

# frozen_string_literal: true

# Creates a Bill in Sway if it does not exist
class SeedBill
  extend T::Sig

  sig { params(sway_locales: T::Array[SwayLocale]).void }
  def self.run(sway_locales)
    sway_locales.each do |sway_locale|
      T.let(read_bills(sway_locale), T::Array[T::Hash[String, String]]).each do |json|
        SeedBill.new.seed(T.let(json, T::Hash[String, String]), sway_locale) if json.fetch("external_id", nil).present?
      end
    end
  end

  sig { params(sway_locale: SwayLocale).returns(T::Array[T::Hash[String, String]]) }
  def self.read_bills(sway_locale)
    T.let(JSON.parse(File.read("storage/seeds/data/#{sway_locale.reversed_name.tr("-", "/")}/bills.json")),
      T::Array[T::Hash[String, String]])
  end

  sig { params(time_string: T.nilable(String)).returns(T.nilable(Time)) }
  def self.time(time_string)
    Time.zone.parse(time_string) if time_string
  end

  def initialize
  end

  sig { params(json: T::Hash[String, T.untyped], sway_locale: SwayLocale).returns(Bill) }
  def seed(json, sway_locale)
    bill = Bill.find_or_initialize_by(
      external_id: json.fetch("external_id", nil)
    )

    bill.external_version = json.fetch("external_version", nil)
    bill.title = json.fetch("title", nil)
    bill.link = json.fetch("link", nil)
    bill.chamber = json.fetch("chamber", nil)
    bill.introduced_date_time_utc = Date.strptime(json.fetch("introduced_date_time_utc", Time.zone.now.strftime("%m/%d/%Y")), "%m/%d/%Y")
    bill.house_vote_date_time_utc = json.fetch("house_vote_date_time_utc", nil)
    bill.senate_vote_date_time_utc = json.fetch("senate_vote_date_time_utc", nil)
    bill.level = json.fetch("level", nil)
    bill.category = json.fetch("category", nil)
    bill.summary = json.fetch("summary", nil)

    bill.legislator = Legislator.where(
      external_id: json.fetch("external_id", nil)
    ).or(
      Legislator.where(
        first_name: T.cast(json, T::Hash[String, T::Hash[String, String]]).dig(
          "legislator", "first_name"
        ),
        last_name: T.cast(json, T::Hash[String, T::Hash[String, String]]).dig(
          "legislator", "last_name"
        )
      )
    ).find { |l| l.sway_locale.eql?(sway_locale) }
    bill.sway_locale = sway_locale

    bill.save!
    bill
  end
end
