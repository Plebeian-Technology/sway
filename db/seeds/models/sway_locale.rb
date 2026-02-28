# typed: true

class SeedSwayLocale
  extend T::Sig

  sig { returns(T::Array[SwayLocale]) }
  def self.run
    T
      .let(read_locales, T::Array[T::Hash[String, String]])
      .map do |json|
        SeedSwayLocale.new.seed(T.let(json, T::Hash[String, String]))
      end
  end

  def self.read_locales
    T.let(
      JSON.parse(
        File.read(Rails.root.join("storage", "seeds", "data", "locales.json")),
      ),
      T::Array[T::Hash[String, String]],
    )
  end

  sig { params(locale_data: T::Hash[String, String]).returns(SwayLocale) }
  def seed(locale_data)
    s =
      SwayLocale.find_or_initialize_by(
        city: locale_data.fetch("city"),
        state: locale_data.fetch("region"),
        country: locale_data.fetch("country"),
      )
    s.current_session_start_date =
      Date.parse(
        locale_data.fetch("currentSessionStartDateISO", Time.zone.today.to_s),
      )
    s.time_zone = locale_data.fetch("time_zone", "America/New_York")
    s.icon_url =
      locale_data.fetch("icon_url", locale_data.fetch("icon_path", "logo.svg"))
    s.save!
    s
  end
end
