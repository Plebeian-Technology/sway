# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

# @lat: [[oss-license-snapshot#Why the snapshot is read from node_modules]]
RSpec.describe Sway::FrontendLicenses do
  # The snapshot shipped empty for months, and both the build log
  # and the page stayed quiet about it.
  it "builds a non-empty snapshot from an installed project" do
    Dir.mktmpdir("frontend-licenses") do |root|
      File.write(File.join(root, "package.json"), {
        "dependencies" => {"@scope/thing" => "^1.0.0", "plain" => "^2.0.0"},
        "devDependencies" => {"a-dev-tool" => "^3.0.0"}
      }.to_json)
      FileUtils.mkdir_p(File.join(root, "node_modules", "@scope", "thing"))
      File.write(File.join(root, "node_modules", "@scope", "thing", "package.json"), {
        "name" => "@scope/thing", "version" => "1.2.3", "license" => "Apache-2.0",
        "homepage" => "https://example.com/thing"
      }.to_json)
      FileUtils.mkdir_p(File.join(root, "node_modules", "plain"))
      File.write(File.join(root, "node_modules", "plain", "package.json"), {
        "name" => "plain", "version" => "2.0.1", "license" => "MIT"
      }.to_json)

      snapshot = described_class.new(root).snapshot

      expect(snapshot).to eq(
        "Apache-2.0" => [{
          "name" => "@scope/thing",
          "versions" => ["1.2.3"],
          "license" => "Apache-2.0",
          "homepage" => "https://example.com/thing"
        }],
        "MIT" => [{
          "name" => "plain",
          "versions" => ["2.0.1"],
          "license" => "MIT",
          "homepage" => nil
        }]
      )
    end
  end

  it "stops and names a dependency that is not installed" do
    Dir.mktmpdir("frontend-licenses") do |root|
      File.write(File.join(root, "package.json"), {"dependencies" => {"absent" => "^1.0.0"}}.to_json)

      expect { described_class.new(root).snapshot }
        .to raise_error(described_class::Error, /not installed under node_modules: absent/)
    end
  end

  it "stops when there is no package.json to read" do
    Dir.mktmpdir("frontend-licenses") do |root|
      expect { described_class.new(root).snapshot }
        .to raise_error(described_class::Error, /no package.json/)
    end
  end

  # npm has spelled the field three ways, and the tree still holds all three.
  it "reads the older spellings of the license field" do
    Dir.mktmpdir("frontend-licenses") do |root|
      File.write(File.join(root, "package.json"), {
        "dependencies" => {"objecty" => "^1.0.0", "arrayey" => "^1.0.0", "silent" => "^1.0.0"}
      }.to_json)
      {
        "objecty" => {"version" => "1.0.0", "license" => {"type" => "BSD-3-Clause"}},
        "arrayey" => {"version" => "1.0.0", "licenses" => [{"type" => "MIT"}, {"type" => "GPL-2.0"}]},
        "silent" => {"version" => "1.0.0"}
      }.each do |name, manifest|
        FileUtils.mkdir_p(File.join(root, "node_modules", name))
        File.write(File.join(root, "node_modules", name, "package.json"), manifest.to_json)
      end

      snapshot = described_class.new(root).snapshot

      expect(snapshot.keys).to match_array(["BSD-3-Clause", "MIT OR GPL-2.0", "UNKNOWN"])
    end
  end

  # The page reads whatever is on disk, so the failure has to arrive as
  # content rather than as an absence.
  it "offers a stand-in snapshot the licences page renders as a row" do
    Dir.mktmpdir("licenses-page") do |dir|
      path = Pathname.new(dir).join("oss-frontend-licenses.json")
      path.write("#{JSON.pretty_generate(described_class::UNAVAILABLE)}\n")
      stub_const("OpenSourceLicensesService::FRONTEND_JSON_PATH", path)

      rendered = OpenSourceLicensesService.call

      expect(rendered.size).to eq(1)
      expect(rendered.first[:license]).to eq("unavailable")
    end
  end
end
