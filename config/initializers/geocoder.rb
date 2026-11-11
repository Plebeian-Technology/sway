Geocoder.configure(
  lookup: Rails.env.test? ? :test : :google,
  ip_lookup: Rails.env.test? ? :test : :ipinfo_io,
  language: :en,
  use_https: true,
  # @lat: [[pre-autoload-credential-trimming#Geocoder (config/initializers/geocoder.rb)]]
  api_key: Rails.env.test? ? nil : ENV["GOOGLE_MAPS_API_KEY"].to_s.strip.presence,
  always_raise: :all,
  units: :mi, # :km for kilometers or :mi for miles
  distances: :linear, # :spherical or :linear
  cache: Geocoder::CacheStore::Generic.new(Rails.cache, {}),
  cache_options: {
    expiration: 2.days,
    prefix: "geocoder:"
  }
)
