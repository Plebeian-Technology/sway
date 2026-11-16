# frozen_string_literal: true

require "rails_helper"

RSpec.describe NormalizeAddressService do
  describe ".call with an Address record (record mode)" do
    it "normalizes full state name to 2-letter uppercase code and titleizes city" do
      address = Address.new(street: "1 Main St", city: "baltimore", region_code: "maryland", postal_code: "21201")
      result = described_class.call(address)

      expect(result).to eq(address)
      expect(address.region_code).to eq("MD")
      expect(address.city).to eq("Baltimore")
    end

    it "upcases lowercase 2-letter region code" do
      address = Address.new(street: "100 N Holliday St", city: "Baltimore", region_code: "md", postal_code: "21202")
      described_class.call(address)

      expect(address.region_code).to eq("MD")
      expect(address.city).to eq("Baltimore")
    end

    it "preserves already uppercase 2-letter region code" do
      address = Address.new(street: "100 N Holliday St", city: "Baltimore", region_code: "MD", postal_code: "21202")
      described_class.call(address)

      expect(address.region_code).to eq("MD")
    end

    it "upcases unrecognized state names longer than 2 characters" do
      address = Address.new(city: "atlantis city", region_code: "atlantis")
      described_class.call(address)

      expect(address.region_code).to eq("ATLANTIS")
      expect(address.city).to eq("Atlantis City")
    end

    it "leaves nil and blank values untouched without raising" do
      address = Address.new(city: nil, region_code: nil)
      expect { described_class.call(address) }.not_to raise_error
      expect(address.city).to be_nil
      expect(address.region_code).to be_nil
    end

    it "preserves non-normalized attributes intact" do
      address = Address.new(
        street: "100 N Holliday Street",
        street2: "Suite 400",
        postal_code: "21202-1234",
        country: "US",
        latitude: "39.291",
        longitude: "-76.610"
      )
      described_class.call(address)

      expect(address.street).to eq("100 N Holliday Street")
      expect(address.street2).to eq("Suite 400")
      expect(address.postal_code).to eq("21202-1234")
      expect(address.country).to eq("US")
      expect(address.latitude).to eq("39.291")
      expect(address.longitude).to eq("-76.610")
    end

    it "supports duck-typed objects responding to city= and region_code=" do
      duck = Struct.new(:city, :region_code).new("annapolis", "maryland")
      result = described_class.call(duck)

      expect(result).to eq(duck)
      expect(duck.city).to eq("Annapolis")
      expect(duck.region_code).to eq("MD")
    end
  end

  describe ".call with attributes / kwargs (hash mode)" do
    it "normalizes city and region_code from kwargs" do
      result = described_class.call(city: "baltimore", region_code: "maryland")

      expect(result).to eq({city: "Baltimore", region_code: "MD"})
    end

    it "normalizes state alias to region_code and sets both keys" do
      result = described_class.call(city: "new york", state: "new york")

      expect(result[:city]).to eq("New York")
      expect(result[:state]).to eq("NY")
      expect(result[:region_code]).to eq("NY")
    end

    it "accepts a hash target with symbolized or string keys" do
      result = described_class.call({"city" => "san francisco", "region_code" => "ca"})

      expect(result[:city]).to eq("San Francisco")
      expect(result[:region_code]).to eq("CA")
    end

    it "preserves additional passed attributes untouched" do
      result = described_class.call(
        street: "100 N Holliday St",
        city: "baltimore",
        region_code: "maryland",
        postal_code: "21202",
        country: "US"
      )

      expect(result).to eq({
        street: "100 N Holliday St",
        city: "Baltimore",
        region_code: "MD",
        postal_code: "21202",
        country: "US"
      })
    end

    it "handles nil and blank attributes safely" do
      result = described_class.call(city: nil, region_code: nil)

      expect(result[:city]).to be_nil
      expect(result[:region_code]).to be_nil
    end

    it "normalizes region_code when :city is omitted" do
      expect(described_class.call(region_code: "maryland")).to eq({region_code: "MD"})
    end
  end

  describe ".normalize_region_code" do
    it "converts full state names in various casings to 2-letter uppercase postal code" do
      expect(described_class.normalize_region_code("maryland")).to eq("MD")
      expect(described_class.normalize_region_code("Maryland")).to eq("MD")
      expect(described_class.normalize_region_code("MARYLAND")).to eq("MD")
      expect(described_class.normalize_region_code("District of Columbia")).to eq("DC")
      expect(described_class.normalize_region_code("puerto rico")).to eq("PR")
      expect(described_class.normalize_region_code("California")).to eq("CA")
    end

    it "upcases 2-letter codes" do
      expect(described_class.normalize_region_code("md")).to eq("MD")
      expect(described_class.normalize_region_code("MD")).to eq("MD")
      expect(described_class.normalize_region_code("va")).to eq("VA")
    end

    it "trims whitespace around state names and codes" do
      expect(described_class.normalize_region_code("  maryland  ")).to eq("MD")
      expect(described_class.normalize_region_code("  md  ")).to eq("MD")
    end

    it "upcases unrecognized regions longer than 2 characters" do
      expect(described_class.normalize_region_code("Narnia")).to eq("NARNIA")
      expect(described_class.normalize_region_code("unknown")).to eq("UNKNOWN")
    end

    it "upcases single-character strings" do
      expect(described_class.normalize_region_code("x")).to eq("X")
    end

    it "returns nil, empty, blank, or zero-width-only strings unchanged" do
      expect(described_class.normalize_region_code(nil)).to be_nil
      expect(described_class.normalize_region_code("")).to eq("")
      expect(described_class.normalize_region_code("   ")).to eq("   ")
      expect(described_class.normalize_region_code("\u200B")).to eq("")
    end
  end

  describe ".normalize_city" do
    it "titleizes lowercase and uppercase city names" do
      expect(described_class.normalize_city("baltimore")).to eq("Baltimore")
      expect(described_class.normalize_city("BALTIMORE")).to eq("Baltimore")
      expect(described_class.normalize_city("new york")).to eq("New York")
      expect(described_class.normalize_city("st. louis")).to eq("St. Louis")
    end

    it "strips leading and trailing whitespace" do
      expect(described_class.normalize_city("  baltimore  ")).to eq("Baltimore")
    end

    it "returns nil, empty, or blank strings unchanged" do
      expect(described_class.normalize_city(nil)).to be_nil
      expect(described_class.normalize_city("")).to eq("")
      expect(described_class.normalize_city("   ")).to eq("   ")
    end
  end

  describe "integration with Address validation lifecycle" do
    it "automatically normalizes attributes when Address#valid? is called" do
      address = Address.new(street: "1 Main", city: "baltimore", region_code: "maryland", postal_code: "21201")
      expect(address.city).to eq("baltimore")
      expect(address.region_code).to eq("maryland")

      address.valid?

      expect(address.city).to eq("Baltimore")
      expect(address.region_code).to eq("MD")
    end
  end
end
