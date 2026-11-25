# frozen_string_literal: true

class AdminLocaleSampleAddressResource < ApplicationResource
  attributes :id,
    :sample_street,
    :sample_postal_code,
    :sample_latitude,
    :sample_longitude
end
