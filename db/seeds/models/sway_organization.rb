# frozen_string_literal: true

# Seeds the Sway organization in every locale. Safe to run repeatedly.
class SeedSwayOrganization
  NAME = "Sway"
  ICON_URL = "/images/sway-us-light.png"

  # @lat: [[domain-entities#Organizations and campaigns]]
  def self.run(locales)
    locales.map do |sway_locale|
      organization = Organization.find_or_create_by!(name: NAME, sway_locale: sway_locale)
      organization.update!(icon_url: ICON_URL) if organization.icon_url.blank?
      organization
    end
  end
end
