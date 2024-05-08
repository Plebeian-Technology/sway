# typed: true

class SeedSwayLocale
  extend T::Sig

  sig { returns(T::Array[SwayLocale]) }
  def self.run
    T.let(read_locales, T::Array[T::Hash[String, String]]).map do |json|
      SeedSwayLocale.new.seed(T.let(json, T::Hash[String, String]))
    end
  end

  def self.read_locales
    T.let(JSON.parse(File.read('storage/seeds/data/locales.json')),
          T::Array[T::Hash[String, String]])
  end

  sig { params(j: T::Hash[String, String]).returns(SwayLocale) }
  def seed(j)
    SwayLocale.find_or_create_by!(
      city: j.fetch('city'),
      state: j.fetch('region'),
      country: j.fetch('country')
    )
  end
end
