# frozen_string_literal: true

class SwayLocaleResource < ApplicationResource
  attributes :id, :slug, :name, :city, :state, :region_code, :country, :generic_portal_urls,
    :nominatim_viewbox, :nominatim_bounded, :nominatim_country_codes
end
