# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe OpenSourceLicensesService do
  describe "#javascript_dependencies" do
    around do |example|
      Dir.mktmpdir do |dir|
        @licenses_dir = dir
        example.run
      end
    end

    before do
      # stub_const has to run inside the per-example setup, not in `around`, so
      # the constant is put back cleanly after each example.
      @licenses_path = Pathname.new(@licenses_dir).join("oss-frontend-licenses.json")
      stub_const("OpenSourceLicensesService::FRONTEND_JSON_PATH", @licenses_path)
    end

    it "returns [] when the snapshot file is missing" do
      expect(described_class.new.javascript_dependencies).to eq([])
    end

    it "flattens the pnpm-shaped json into sorted, normalized rows" do
      @licenses_path.write(
        {
          "Apache-2.0" => [
            {"name" => "class-variance-authority", "versions" => ["0.7.1"], "license" => "Apache-2.0", "homepage" => "https://cva.style"}
          ],
          "BSD-3-Clause" => [
            {"name" => "diff", "versions" => ["8.0.4"], "homepage" => nil}
          ]
        }.to_json
      )

      deps = described_class.new.javascript_dependencies

      expect(deps.pluck(:name)).to eq(["class-variance-authority", "diff"])

      cva = deps.find { |dep| dep[:name] == "class-variance-authority" }
      expect(cva[:version]).to eq("0.7.1")
      expect(cva[:license]).to eq("Apache-2.0")
      expect(cva).not_to have_key(:ecosystem)

      diff = deps.find { |dep| dep[:name] == "diff" }
      expect(diff[:license]).to eq("BSD-3-Clause") # falls back to the license group key
    end

    it "omits MIT-licensed packages (non-MIT only)" do
      @licenses_path.write(
        {
          "MIT" => [
            {"name" => "clsx", "versions" => ["2.1.1"], "license" => "MIT", "homepage" => "https://github.com/lukeed/clsx"}
          ],
          "ISC" => [
            {"name" => "lucide-react", "versions" => ["1.17.0"], "license" => "ISC", "homepage" => nil}
          ]
        }.to_json
      )

      deps = described_class.new.javascript_dependencies

      expect(deps.pluck(:name)).to eq(["lucide-react"])
      expect(deps.pluck(:license)).not_to include("MIT")
    end

    it "returns [] on malformed json (degrades gracefully)" do
      @licenses_path.write("{not valid json")
      expect(described_class.new.javascript_dependencies).to eq([])
    end
  end

  describe ".call" do
    it "returns a json-safe array of non-MIT frontend dependencies" do
      result = described_class.call

      expect(result).to be_an(Array)
      result.each do |dep|
        expect(dep).to include(:name, :version, :license, :homepage)
        expect(dep[:license]).not_to eq("MIT")
      end
    end
  end
end
