# frozen_string_literal: true

require "rails_helper"

RSpec.describe "NormalizeAddressService Adversarial Stress Harness" do
  describe "1. Extreme whitespace variations" do
    it "handles leading, trailing, and standard whitespace in city and region" do
      inputs = [
        {city: "  baltimore  ", region: "  maryland  ", exp_city: "Baltimore", exp_reg: "MD"},
        {city: "\t\nbaltimore\r\n", region: "\t\nmaryland\r\n", exp_city: "Baltimore", exp_reg: "MD"},
        {city: "\t\r\n", region: "\t\r\n", exp_city: "\t\r\n", exp_reg: "\t\r\n"},
        {city: "   ", region: "   ", exp_city: "   ", exp_reg: "   "}
      ]

      inputs.each do |input|
        res = NormalizeAddressService.call(city: input[:city], region_code: input[:region])
        expect(res[:city]).to eq(input[:exp_city]), "Failed city for #{input.inspect}"
        expect(res[:region_code]).to eq(input[:exp_reg]), "Failed region for #{input.inspect}"
      end
    end

    it "demonstrates that internal multiple spaces are preserved by titleize" do
      # ActiveSupport titleize preserves internal spaces
      res = NormalizeAddressService.call(city: "  new   york  ", region_code: "  new   york  ")
      expect(res[:city]).to eq("New   York")
      # RegionUtil fails to find :"New   York" in STATE_NAMES_CODES (which has single space),
      # so it falls back to the upcased string
      expect(res[:region_code]).to eq("NEW   YORK")
    end

    it "handles 2-letter codes wrapped in extreme whitespace" do
      expect(NormalizeAddressService.normalize_region_code("   md   ")).to eq("MD")
      expect(NormalizeAddressService.normalize_region_code("\t\nva\r\n")).to eq("VA")
      expect(NormalizeAddressService.normalize_region_code("  DC  ")).to eq("DC")
    end
  end

  describe "2. Unusual capitalization (ALL CAPS, all lowercase, Title Case)" do
    it "normalizes standard casing styles correctly" do
      cases = [
        {city: "BALTIMORE", region: "MARYLAND", exp_city: "Baltimore", exp_reg: "MD"},
        {city: "baltimore", region: "maryland", exp_city: "Baltimore", exp_reg: "MD"},
        {city: "District of Columbia", region: "District of Columbia", exp_city: "District Of Columbia", exp_reg: "DC"},
        {city: "Puerto Rico", region: "Puerto Rico", exp_city: "Puerto Rico", exp_reg: "PR"},
        {city: "SAN FRANCISCO", region: "CALIFORNIA", exp_city: "San Francisco", exp_reg: "CA"},
        {city: "san francisco", region: "california", exp_city: "San Francisco", exp_reg: "CA"}
      ]

      cases.each do |c|
        res = NormalizeAddressService.call(city: c[:city], region_code: c[:region])
        expect(res[:city]).to eq(c[:exp_city]), "Failed city casing for #{c.inspect}"
        expect(res[:region_code]).to eq(c[:exp_reg]), "Failed region casing for #{c.inspect}"
      end
    end

    it "documents camelCase / spongecase behavior under ActiveSupport titleize" do
      # ActiveSupport titleize splits on camelCase boundaries (e.g. bAlTiMoRe -> B Al Ti Mo Re)
      expect(NormalizeAddressService.normalize_city("bAlTiMoRe")).to eq("B Al Ti Mo Re")
      # And in RegionUtil, "mArYlAnD".titleize becomes "M Ar Yl An D", which misses STATE_NAMES_CODES
      # and falls back to upcasing
      expect(NormalizeAddressService.normalize_region_code("mArYlAnD")).to eq("MARYLAND")
    end

    it "upcases mixed-case 2-letter region codes" do
      %w[md Md mD MD va Va vA VA ca Ca cA CA ny Ny nY NY].each do |code|
        expect(NormalizeAddressService.normalize_region_code(code)).to eq(code.upcase)
      end
    end
  end

  describe "3. All 50 US States, DC, and Territories" do
    it "resolves every single full state and territory name to its 2-letter code across multiple casing formats" do
      all_states_and_territories = RegionUtil::STATE_NAMES_CODES
      all_states_and_territories.each do |full_name, expected_code|
        name_str = full_name.to_s

        # Titlecase
        expect(NormalizeAddressService.normalize_region_code(name_str)).to eq(expected_code),
          "Failed for standard #{name_str}"

        # Lowercase
        expect(NormalizeAddressService.normalize_region_code(name_str.downcase)).to eq(expected_code),
          "Failed for downcase #{name_str.downcase}"

        # Uppercase
        expect(NormalizeAddressService.normalize_region_code(name_str.upcase)).to eq(expected_code),
          "Failed for upcase #{name_str.upcase}"

        # Padded with whitespace
        expect(NormalizeAddressService.normalize_region_code("  #{name_str}  ")).to eq(expected_code),
          "Failed for padded #{name_str}"
      end
    end

    it "preserves and upcases every 2-letter state/territory code" do
      all_states_and_territories = RegionUtil::STATE_NAMES_CODES
      all_states_and_territories.each_value do |code|
        expect(NormalizeAddressService.normalize_region_code(code.downcase)).to eq(code)
        expect(NormalizeAddressService.normalize_region_code(code.upcase)).to eq(code)
        expect(NormalizeAddressService.normalize_region_code("  #{code.downcase}  ")).to eq(code)
      end
    end
  end

  describe "4. Non-US, unknown, or numeric strings" do
    it "upcases unrecognized region names longer than 2 characters" do
      expect(NormalizeAddressService.normalize_region_code("Narnia")).to eq("NARNIA")
      expect(NormalizeAddressService.normalize_region_code("mars")).to eq("MARS")
      expect(NormalizeAddressService.normalize_region_code("Middle Earth")).to eq("MIDDLE EARTH")
      expect(NormalizeAddressService.normalize_region_code("Westeros")).to eq("WESTEROS")
    end

    it "handles numeric or special character region strings" do
      expect(NormalizeAddressService.normalize_region_code("12345")).to eq("12345")
      expect(NormalizeAddressService.normalize_region_code("99")).to eq("99")
      expect(NormalizeAddressService.normalize_region_code("a")).to eq("A")
      expect(NormalizeAddressService.normalize_region_code("D.C.")).to eq("D.C.")
    end

    it "titleizes exotic city strings according to ActiveSupport conventions" do
      expect(NormalizeAddressService.normalize_city("king's landing")).to eq("King's Landing")
      expect(NormalizeAddressService.normalize_city("123 main")).to eq("123 Main")
      expect(NormalizeAddressService.normalize_city("new york-newark")).to eq("New York Newark")
    end
  end

  describe "5. Nil, empty strings, symbols, and non-string types" do
    it "safely handles nil, empty strings, and whitespace-only strings" do
      expect(NormalizeAddressService.normalize_city(nil)).to be_nil
      expect(NormalizeAddressService.normalize_city("")).to eq("")
      expect(NormalizeAddressService.normalize_city("   ")).to eq("   ")

      expect(NormalizeAddressService.normalize_region_code(nil)).to be_nil
      expect(NormalizeAddressService.normalize_region_code("")).to eq("")
      expect(NormalizeAddressService.normalize_region_code("   ")).to eq("   ")
    end

    it "handles symbols by converting to string" do
      res = NormalizeAddressService.call(city: :baltimore, region_code: :maryland)
      expect(res[:city]).to eq("Baltimore")
      expect(res[:region_code]).to eq("MD")

      res2 = NormalizeAddressService.call(region_code: :md)
      expect(res2[:region_code]).to eq("MD")
    end

    it "handles integer inputs gracefully" do
      expect(NormalizeAddressService.normalize_region_code(21201)).to eq("21201")
      expect(NormalizeAddressService.normalize_city(42)).to eq("42")
    end

    it "handles unexpected target types without blowing up" do
      expect(NormalizeAddressService.call(nil)).to eq({})
      expect(NormalizeAddressService.call("some random string")).to eq({})
      expect(NormalizeAddressService.call(12345)).to eq({})
    end
  end

  describe "6. Idempotence verification" do
    it "satisfies NormalizeAddressService.call(NormalizeAddressService.call(x)) == NormalizeAddressService.call(x)" do
      test_hashes = [
        {city: "baltimore", region_code: "maryland"},
        {city: "NEW YORK", region_code: "NEW YORK"},
        {city: "san francisco", state: "ca"},
        {city: "  chicago  ", region_code: "  illinois  "},
        {city: "Narnia City", region_code: "Narnia"},
        {city: nil, region_code: nil},
        {city: "", region_code: ""},
        {street: "1 Main St", city: "austin", region_code: "texas", postal_code: "78701"}
      ]

      test_hashes.each do |hash|
        first_pass = NormalizeAddressService.call(hash)
        second_pass = NormalizeAddressService.call(first_pass)
        expect(second_pass).to eq(first_pass), "Idempotence failed for #{hash.inspect}"
      end
    end

    it "is idempotent on Address ActiveRecord instances" do
      address = Address.new(street: "1 Main St", city: "baltimore", region_code: "maryland", postal_code: "21201")
      NormalizeAddressService.call(address)
      snapshot_city = address.city
      snapshot_region = address.region_code

      NormalizeAddressService.call(address)
      expect(address.city).to eq(snapshot_city)
      expect(address.region_code).to eq(snapshot_region)
    end
  end

  describe "7. Mutation vs Return Value Verification" do
    it "mutates Address instances in-place and returns the same object" do
      address = Address.new(
        street: "100 N Holliday St",
        street2: "Room 400",
        city: "baltimore",
        region_code: "maryland",
        postal_code: "21202",
        country: "US"
      )

      returned = NormalizeAddressService.call(address)
      expect(returned).to equal(address)
      expect(address.city).to eq("Baltimore")
      expect(address.region_code).to eq("MD")
      # Other attributes remain unmutated
      expect(address.street).to eq("100 N Holliday St")
      expect(address.street2).to eq("Room 400")
      expect(address.postal_code).to eq("21202")
      expect(address.country).to eq("US")
    end

    it "does NOT mutate the input Hash in hash mode" do
      original_hash = {city: "baltimore", region_code: "maryland", street: "1 Main St"}.freeze
      result = NormalizeAddressService.call(original_hash)

      expect(result).not_to equal(original_hash)
      expect(result[:city]).to eq("Baltimore")
      expect(result[:region_code]).to eq("MD")
      expect(result[:street]).to eq("1 Main St")
      expect(original_hash[:city]).to eq("baltimore")
      expect(original_hash[:region_code]).to eq("maryland")
    end
  end

  describe "8. Address ActiveRecord Lifecycle and Validation Timing" do
    it "normalizes address attributes in before_validation callback" do
      address = Address.new(city: "baltimore", region_code: "maryland")
      expect(address.city).to eq("baltimore")
      expect(address.region_code).to eq("maryland")

      address.valid?

      expect(address.city).to eq("Baltimore")
      expect(address.region_code).to eq("MD")
    end

    it "ensures full_address uses normalized city and region before geocoding runs" do
      address = Address.new(
        street: "100 N Holliday St",
        city: "baltimore",
        region_code: "maryland",
        postal_code: "21202"
      )

      # Trigger validation
      address.valid?

      expect(address.city).to eq("Baltimore")
      expect(address.region_code).to eq("MD")
      expect(address.latitude).to be_present
      expect(address.longitude).to be_present
    end
  end

  describe "9. Invisible Unicode spaces" do
    it "removes non-breaking and zero-width spaces from a state code or name" do
      expect(NormalizeAddressService.normalize_region_code("MD\u00A0")).to eq("MD")
      expect(NormalizeAddressService.normalize_region_code("\u00A0md\u00A0")).to eq("MD")
      expect(NormalizeAddressService.normalize_region_code("Maryland\u200B")).to eq("MD")
      expect(NormalizeAddressService.normalize_region_code("M\u200BD")).to eq("MD")
    end

    it "removes non-breaking and zero-width spaces from a city" do
      expect(NormalizeAddressService.normalize_city("Baltimore\u00A0")).to eq("Baltimore")
      expect(NormalizeAddressService.normalize_city("\u200BBaltimore")).to eq("Baltimore")
    end

    it "turns an interior non-breaking space into an ordinary space" do
      expect(NormalizeAddressService.normalize_city("New\u00A0York")).to eq("New York")
    end

    it "is idempotent on cleaned input" do
      once = NormalizeAddressService.call(city: "Baltimore\u00A0", region_code: "Maryland\u200B")
      expect(NormalizeAddressService.call(once)).to eq(once)
    end

    it "returns an empty string for text made only of zero-width characters" do
      expect(NormalizeAddressService.normalize_region_code("\u200B\uFEFF")).to eq("")
      expect(NormalizeAddressService.normalize_city("\u200B\u2060")).to eq("")
    end

    it "cleans city and state on an Address before validation" do
      address = Address.new(city: "Baltimore\u00A0", region_code: "MD\u00A0")

      address.valid?

      expect(address.city).to eq("Baltimore")
      expect(address.region_code).to eq("MD")
    end
  end
end
