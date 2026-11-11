module RegionUtil
  def self.from_country_code_to_name(code)
    return nil if code.blank?
    return code.titlecase.strip if code.length > 2

    COUNTRY_CODES_NAMES.fetch(code.upcase.strip.to_sym, code)
  end

  COUNTRY_CODES_NAMES = {
    US: "United States"
  }.freeze

  def self.from_region_name_to_region_code(name)
    return nil if name.blank?
    return name.upcase.strip if name.length == 2

    RegionUtil::STATE_NAMES_CODES.fetch(name.titleize.strip.to_sym, name)
  end

  def self.from_region_code_to_region_name(code)
    return nil if code.blank?
    return code.titlecase.strip if code.length > 2

    RegionUtil::STATE_CODES_NAMES.fetch(code.upcase.strip.to_sym, code)
  end

  STATE_NAMES_CODES = {
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
  }.freeze

  STATE_CODES_NAMES = STATE_NAMES_CODES.to_h { |name, code| [code.to_sym, name.to_s] }.freeze
end
