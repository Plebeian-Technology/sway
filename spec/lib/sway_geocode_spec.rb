# frozen_string_literal: true

require "rails_helper"
require "sway_geocode"

RSpec.describe SwayGeocode do
  # Congress and Local used to sit inside `class << self`, which defined them on
  # the module's singleton class, so `SwayGeocode::Congress` did not resolve like
  # a normal nested constant. They now live at the module level, and both resolve
  # from outside.
  describe "class structure" do
    it "exposes Congress and Local as ordinary module-nested classes" do
      expect(SwayGeocode::Congress).to be_a(Class)
      expect(SwayGeocode::Local).to be_a(Class)
    end

    it "does not include the (no-op) Census module in Congress" do
      expect(SwayGeocode::Congress.include?(Census)).to be(false)
    end
  end

  describe ".build" do
    let(:address) { build_stubbed(:address) }

    it "builds a Congress geocoder for a congressional locale" do
      sway_locale = instance_double(SwayLocale, congress?: true)
      expect(SwayGeocode.build(sway_locale, address)).to be_a(SwayGeocode::Congress)
    end

    it "builds a Local geocoder for a non-congressional locale" do
      sway_locale = instance_double(SwayLocale, congress?: false)
      expect(SwayGeocode.build(sway_locale, address)).to be_a(SwayGeocode::Local)
    end
  end
end
