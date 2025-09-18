# typed: true

module RegionUtil
  extend T::Sig

  sig { params(name: String).returns(T.nilable(String)) }
  def self.from_country_name_to_code(name)
    return nil if name.blank?
    return name.upcase.strip if name.length == 2

    T.let(COUNTRY_CODES_NAMES.fetch(name.titlecase.strip.to_sym, name), T.nilable(String))
  end

  sig { params(code: String).returns(T.nilable(String)) }
  def self.from_country_code_to_name(code)
    return nil if code.blank?
    return code.titlecase.strip if code.length > 2

    T.let(COUNTRY_CODES_NAMES.fetch(code.upcase.strip.to_sym, code), T.nilable(String))
  end

  COUNTRY_NAMES_CODES = {
    "United States": "US"
  }
  COUNTRY_CODES_NAMES = {
    US: "United States"
  }

  sig { params(name: String).returns(T.nilable(String)) }
  def self.from_region_name_to_region_code(name)
    return nil if name.blank?
    return name.upcase.strip if name.length == 2

    T.let(RegionUtil::STATE_NAMES_CODES.fetch(name.titleize.strip.to_sym, name), T.nilable(String))
  end

  sig { params(code: String).returns(T.nilable(String)) }
  def self.from_region_code_to_region_name(code)
    return nil if code.blank?
    return code.titlecase.strip if code.length > 2

    T.let(RegionUtil::STATE_CODES_NAMES.fetch(code.upcase.strip.to_sym, code), T.nilable(String))
  end

  STATE_NAMES_CODES = T.let({
    "United States": "US", # POTUS
    Alabama: "AL",
    Alaska: "AK",
    "American Samoa": "AS",
    Arizona: "AZ",
    Arkansas: "AR",
    California: "CA",
    Colorado: "CO",
    Connecticut: "CT",
    Delaware: "DE",
    "District Of Columbia": "DC",
    "Federated States Of Micronesia": "FM",
    Florida: "FL",
    Georgia: "GA",
    Guam: "GU",
    Hawaii: "HI",
    Idaho: "ID",
    Illinois: "IL",
    Indiana: "IN",
    Iowa: "IA",
    Kansas: "KS",
    Kentucky: "KY",
    Louisiana: "LA",
    Maine: "ME",
    "Marshall Islands": "MH",
    Maryland: "MD",
    Massachusetts: "MA",
    Michigan: "MI",
    Minnesota: "MN",
    Mississippi: "MS",
    Missouri: "MO",
    Montana: "MT",
    Nebraska: "NE",
    Nevada: "NV",
    "New Hampshire": "NH",
    "New Jersey": "NJ",
    "New Mexico": "NM",
    "New York": "NY",
    "North Carolina": "NC",
    "North Dakota": "ND",
    "Northern Mariana Islands": "MP",
    Ohio: "OH",
    Oklahoma: "OK",
    Oregon: "OR",
    Palau: "PW",
    Pennsylvania: "PA",
    "Puerto Rico": "PR",
    "Rhode Island": "RI",
    "South Carolina": "SC",
    "South Dakota": "SD",
    Tennessee: "TN",
    Texas: "TX",
    Utah: "UT",
    Vermont: "VT",
    "Virgin Islands": "VI",
    Virginia: "VA",
    Washington: "WA",
    "West Virginia": "WV",
    Wisconsin: "WI",
    Wyoming: "WY"
  }, T::Hash[Symbol, String])

  STATE_CODES_NAMES = T.let({
    US: "United States", # POTUS
    AL: "Alabama",
    AK: "Alaska",
    AS: "American Samoa",
    AZ: "Arizona",
    AR: "Arkansas",
    CA: "California",
    CO: "Colorado",
    CT: "Connecticut",
    DE: "Delaware",
    DC: "District Of Columbia",
    FM: "Federated States Of Micronesia",
    FL: "Florida",
    GA: "Georgia",
    GU: "Guam",
    HI: "Hawaii",
    ID: "Idaho",
    IL: "Illinois",
    IN: "Indiana",
    IA: "Iowa",
    KS: "Kansas",
    KY: "Kentucky",
    LA: "Louisiana",
    ME: "Maine",
    MH: "Marshall Islands",
    MD: "Maryland",
    MA: "Massachusetts",
    MI: "Michigan",
    MN: "Minnesota",
    MS: "Mississippi",
    MO: "Missouri",
    MT: "Montana",
    NE: "Nebraska",
    NV: "Nevada",
    NH: "New Hampshire",
    NJ: "New Jersey",
    NM: "New Mexico",
    NY: "New York",
    NC: "North Carolina",
    ND: "North Dakota",
    MP: "Northern Mariana Islands",
    OH: "Ohio",
    OK: "Oklahoma",
    OR: "Oregon",
    PW: "Palau",
    PA: "Pennsylvania",
    PR: "Puerto Rico",
    RI: "Rhode Island",
    SC: "South Carolina",
    SD: "South Dakota",
    TN: "Tennessee",
    TX: "Texas",
    UT: "Utah",
    VT: "Vermont",
    VI: "Virgin Islands",
    VA: "Virginia",
    WA: "Washington",
    WV: "West Virginia",
    WI: "Wisconsin",
    WY: "Wyoming"
  }, T::Hash[Symbol, String])
end
