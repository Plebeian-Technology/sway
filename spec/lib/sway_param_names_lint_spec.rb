# frozen_string_literal: true

require "rails_helper"
require "rake"
require "tmpdir"
require "fileutils"
require "yaml"
require "json"
require "open3"
require_relative "../../lib/query_parameter_check"

# @lat: [[query-parameter-namespaces#Machine-readable registry and lint enforcement]]
RSpec.describe "sway:lint:param_names and QueryParameterCheck" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("sway:lint:param_names")
  end

  before do
    Rake::Task["sway:lint:param_names"].reenable
  end

  def write_temp_registry(dir, content)
    path = File.join(dir, "config", "query_parameters.yml")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  def write_feature_registry(dir, features:, global_ambient: [])
    definitions = features.to_h do |name, parameters|
      [name, {
        "parameters" => parameters,
        "route_patterns" => ["^/#{name}"],
        "parameter_families" => parameters.to_h { |parameter| [parameter, []] }
      }]
    end
    write_temp_registry(dir, YAML.dump("features" => definitions, "global_ambient" => global_ambient))
  end

  describe QueryParameterCheck do
    it "passes cleanly against the real repository registry" do
      check = described_class.new(Rails.root.to_s)
      expect(check.offences).to be_empty
      expect(check.scanned_count).to be >= 20
      expect(check.features.keys).to contain_exactly(
        "bill_creator", "bills", "feed", "legislators", "notifications", "organizations"
      )
      expect(check.canonical_parameters["bill_creator"]).to eq(
        [
          "bill_creator_tab",
          "bill_creator_sort",
          "selected_stages",
          "download_missing_assets",
          "subject",
          "severity",
          "window",
          "cursor",
          "date",
          "highlight"
        ]
      )
      expect(check.canonical_parameters["bills"]).to eq(
        ["bills_sort", "bills_direction", "bills_page", "bills_search", "bills_legislative_session_id"]
      )
      expect(check.canonical_parameters["legislators"]).to eq(
        ["legislators_tab", "legislators_search"]
      )
      expect(check.canonical_parameters["notifications"]).to eq(["notifications_tab"])
      expect(check.canonical_parameters["organizations"]).to eq(["org_tab", "org_search"])
      expect(check.global_ambient).to eq(
        ["sway_locale_id", "run_id", "highlight_bill_id"]
      )
    end

    it "resolves routes and parameter aliases from the checked registry" do
      check = described_class.new(Rails.root.to_s)

      expect(check.feature_for_path("/admin/bill_creator/12")).to eq("bill_creator")
      expect(check.feature_for_path("/unregistered/path")).to be_nil
      expect(check.parameter_family("organizations", "tab_key")).to eq(["org_tab", "tab", "tab_key"])
      expect(check.parameter_family("bill_creator", "stages[]")).to eq(["selected_stages", "stages"])
      expect(check.parameter_family("bills", "unknown")).to eq([])
    end

    it "fails closed when multiple feature route patterns claim the same path" do
      Dir.mktmpdir do |dir|
        write_temp_registry(dir, YAML.dump(
          "features" => {
            "bills" => {
              "parameters" => ["bills_search"],
              "route_patterns" => ["^/shared"],
              "parameter_families" => {"bills_search" => []}
            },
            "organizations" => {
              "parameters" => ["org_tab"],
              "route_patterns" => ["^/shared"],
              "parameter_families" => {"org_tab" => []}
            }
          }
        ))

        expect(described_class.new(dir).feature_for_path("/shared/12")).to be_nil
      end
    end

    it "rejects route patterns with Ruby-only anchors" do
      Dir.mktmpdir do |dir|
        write_temp_registry(dir, YAML.dump(
          "features" => {
            "bills" => {
              "parameters" => ["bills_search"],
              "route_patterns" => ["\\A/bills"],
              "parameter_families" => {"bills_search" => []}
            }
          }
        ))

        expect { described_class.new(dir).features }.to raise_error(
          QueryParameterCheck::InvalidRegistryError,
          /not portable between Ruby and JavaScript/
        )
      end
    end

    it "rejects Ruby character classes whose JavaScript meaning differs" do
      ["[[:digit:]]", "[a-z&&[^aeiou]]"].each do |pattern|
        Dir.mktmpdir do |dir|
          write_temp_registry(dir, YAML.dump(
            "features" => {
              "bills" => {
                "parameters" => ["bills_search"],
                "route_patterns" => [pattern],
                "parameter_families" => {"bills_search" => []}
              }
            }
          ))

          expect { described_class.new(dir).features }.to raise_error(
            QueryParameterCheck::InvalidRegistryError,
            /not portable between Ruby and JavaScript/
          )
        end
      end
    end

    it "matches the frontend's declared registry projection" do
      check = described_class.new(Rails.root.to_s)
      stdout, stderr, status = Open3.capture3(
        "pnpm", "exec", "tsx", Rails.root.join("spec", "support", "query_parameter_registry_projection.ts").to_s,
        chdir: Rails.root.to_s
      )

      expect(status.success?).to be(true), stderr
      expect(JSON.parse(stdout)).to eq(JSON.parse(JSON.generate(check.registry_projection)))
    end

    it "flags collisions when multiple features claim the same canonical parameter and names both claimants" do
      Dir.mktmpdir do |dir|
        write_feature_registry(dir, features: {"bills" => ["shared_search"], "legislators" => ["shared_search"]})

        check = described_class.new(dir)
        offences = check.offences

        expect(offences.length).to eq(1)
        expect(offences.first.to_s).to include("Parameter 'shared_search' is claimed by multiple features: bills, legislators")
      end
    end

    it "flags collisions between a feature canonical parameter and global ambient parameters" do
      Dir.mktmpdir do |dir|
        write_feature_registry(dir, features: {"bills" => ["run_id"]}, global_ambient: ["run_id"])

        check = described_class.new(dir)
        offences = check.offences

        expect(offences.length).to eq(1)
        expect(offences.first.to_s).to include(
          "Parameter 'run_id' is claimed by feature 'bills' and declared as global ambient"
        )
      end
    end

    it "flags duplicate parameters within the same feature" do
      Dir.mktmpdir do |dir|
        write_feature_registry(dir, features: {"bills" => ["bills_search", "bills_search"]})

        check = described_class.new(dir)
        offences = check.offences

        expect(offences.length).to eq(1)
        expect(offences.first.to_s).to include(
          "Feature 'bills' declares duplicate parameter 'bills_search'"
        )
      end
    end

    it "flags duplicate global ambient parameters" do
      Dir.mktmpdir do |dir|
        write_feature_registry(dir, features: {"bills" => ["bills_search"]}, global_ambient: ["run_id", "run_id"])

        check = described_class.new(dir)
        offences = check.offences

        expect(offences.length).to eq(1)
        expect(offences.first.to_s).to include(
          "Global ambient parameter 'run_id' is declared multiple times"
        )
      end
    end

    it "rejects duplicated aliases and requires a family for each canonical parameter" do
      Dir.mktmpdir do |dir|
        write_temp_registry(dir, YAML.dump(
          "features" => {
            "bills" => {
              "parameters" => ["bills_sort", "bills_search"],
              "route_patterns" => ["^/bills"],
              "parameter_families" => {"bills_sort" => ["sort"], "bills_search" => ["sort"]}
            }
          }
        ))
        expect { described_class.new(dir).features }.to raise_error(
          QueryParameterCheck::InvalidRegistryError, /assigns aliases to multiple families/
        )
      end

      Dir.mktmpdir do |dir|
        write_temp_registry(dir, YAML.dump(
          "features" => {
            "bills" => {
              "parameters" => ["bills_sort", "bills_search"],
              "route_patterns" => ["^/bills"],
              "parameter_families" => {"bills_sort" => []}
            }
          }
        ))
        expect { described_class.new(dir).features }.to raise_error(
          QueryParameterCheck::InvalidRegistryError, /missing parameter families for: bills_search/
        )
      end
    end

    it "raises EmptyRegistryError on an empty registry file" do
      Dir.mktmpdir do |dir|
        write_temp_registry(dir, "")
        check = described_class.new(dir)

        expect { check.offences }.to raise_error(
          QueryParameterCheck::EmptyRegistryError,
          /is empty/
        )
      end
    end

    it "raises EmptyRegistryError when features mapping is empty" do
      Dir.mktmpdir do |dir|
        write_temp_registry(dir, "features: {}\n")
        check = described_class.new(dir)

        expect { check.offences }.to raise_error(
          QueryParameterCheck::EmptyRegistryError,
          /Missing or empty 'features' section/
        )
      end
    end

    it "raises MissingRegistryFileError when the registry file does not exist" do
      Dir.mktmpdir do |dir|
        check = described_class.new(dir)

        expect { check.offences }.to raise_error(
          QueryParameterCheck::MissingRegistryFileError,
          /Registry file not found/
        )
      end
    end

    it "raises InvalidRegistryError when features is not a hash" do
      Dir.mktmpdir do |dir|
        write_temp_registry(dir, "features:\n  - not_a_hash\n")
        check = described_class.new(dir)

        expect { check.offences }.to raise_error(
          QueryParameterCheck::InvalidRegistryError,
          /'features' must be a Hash/
        )
      end
    end
  end

  describe "rake task execution" do
    it "passes on the current repository tree" do
      expect { Rake::Task["sway:lint:param_names"].invoke }.not_to raise_error
    end

    it "aborts with non-zero exit when parameter collisions are present" do
      fake_offence = QueryParameterCheck::Offence.new(
        "Parameter 'colliding' is claimed by multiple features: feature_a, feature_b"
      )
      fake_check = instance_double(
        QueryParameterCheck,
        offences: [fake_offence],
        scanned_count: 2,
        features: {"feature_a" => {}, "feature_b" => {}}
      )
      allow(QueryParameterCheck).to receive(:new).and_return(fake_check)

      expect { Rake::Task["sway:lint:param_names"].invoke }.to raise_error(SystemExit)
    end

    it "aborts loud when the registry is empty" do
      fake_check = instance_double(QueryParameterCheck)
      allow(QueryParameterCheck).to receive(:new).and_return(fake_check)
      allow(fake_check).to receive(:offences).and_raise(
        QueryParameterCheck::EmptyRegistryError, "registry is empty"
      )

      expect { Rake::Task["sway:lint:param_names"].invoke }.to raise_error(SystemExit)
    end
  end
end
