# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "seeds", "models", "sway_locale")
require Rails.root.join("db", "seeds", "models", "sway_organization")

RSpec.describe SeedSwayOrganization do
  describe ".run" do
    # @lat: [[domain-entities#Organizations and campaigns]]
    it "seeds a Sway organization with Sway's own icon in every locale" do
      locales = SeedSwayLocale.run

      expect { described_class.run(locales) }.to change(Organization, :count).by(locales.size)

      locales.each do |sway_locale|
        organization = Organization.find_by!(name: "Sway", sway_locale: sway_locale)
        expect(organization.icon_url).to eq("/images/sway-us-light.png")
      end
    end

    it "creates nothing on a second run" do
      locales = SeedSwayLocale.run
      described_class.run(locales)

      expect { described_class.run(locales) }.not_to change(Organization, :count)
    end

    it "keeps an icon somebody has changed" do
      locales = SeedSwayLocale.run
      described_class.run(locales)
      organization = Organization.find_by!(name: "Sway", sway_locale: locales.first)
      organization.update_columns(icon_url: "/images/other.png")

      described_class.run(locales)

      expect(organization.reload.icon_url).to eq("/images/other.png")
    end
  end
end
