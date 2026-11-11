# frozen_string_literal: true

require "rails_helper"
require "yaml"

RSpec.describe BackupLegislationArtifactsJob do
  let(:backup_report) { Legislation::ArtifactBackupReport.new }
  let(:service) { instance_double(Legislation::ArtifactBackupService, call: backup_report) }

  before do
    allow(Legislation::ArtifactBackupService).to receive(:new).and_return(service)
  end

  describe "#perform" do
    it "returns quietly when the pass finished clean" do
      backup_report.status = :ok

      expect { described_class.new.perform }.not_to raise_error
    end

    it "raises when the bucket could not be listed" do
      backup_report.status = :listing_failed

      expect { described_class.new.perform }
        .to raise_error(described_class::BackupIncomplete, /listing_failed/)
    end

    it "raises when the walk found less than the database implies" do
      backup_report.status = :floor_not_met
      backup_report.floor = 12

      expect { described_class.new.perform }
        .to raise_error(described_class::BackupIncomplete, /floor_not_met/)
    end

    it "raises when the pass completed but individual uploads failed" do
      backup_report.status = :ok
      backup_report.record_failure("legislation/production/law/charter.md", "Google::Cloud::Error: nope")

      expect { described_class.new.perform }
        .to raise_error(described_class::BackupIncomplete, /1 failed/)
    end

    it "includes bounded failed-object details in the BackupIncomplete message" do
      backup_report.status = :ok
      backup_report.record_failure("bills/maryland/b1.json", "Net::ReadTimeout")
      backup_report.record_failure("law/maryland/raw/gab.pdf", "Errno::ENOENT")

      expect { described_class.new.perform }
        .to raise_error(
          described_class::BackupIncomplete,
          /2 failed.*bills\/maryland\/b1\.json \(Net::ReadTimeout\), law\/maryland\/raw\/gab\.pdf \(Errno::ENOENT\)/
        )
    end

    it "defines MAX_REPORTED_FAILURES as 5" do
      expect(described_class::MAX_REPORTED_FAILURES).to eq(5)
    end

    it "truncates failed-object details with (+N more) when more than 5 objects fail" do
      backup_report.status = :ok
      (1..7).each do |i|
        backup_report.record_failure("file#{i}.json", "Error #{i}")
      end

      expect { described_class.new.perform }
        .to raise_error(
          described_class::BackupIncomplete,
          /file1\.json \(Error 1\).*file5\.json \(Error 5\) \(\+2 more\)/
        )
    end

    it "formats all failed objects without truncation when failed count is exactly 5" do
      backup_report.status = :ok
      (1..5).each do |i|
        backup_report.record_failure("file#{i}.json", "Error #{i}")
      end

      expect { described_class.new.perform }
        .to raise_error do |err|
          expect(err).to be_a(described_class::BackupIncomplete)
          expect(err.message).to include("5 failed")
          expect(err.message).to include(
            "file1.json (Error 1), file2.json (Error 2), file3.json (Error 3), " \
            "file4.json (Error 4), file5.json (Error 5)"
          )
          expect(err.message).not_to include("(+")
        end
    end

    it "reads report.failed directly and does not call nonexistent report.errors" do
      backup_report.status = :ok
      backup_report.record_failure("file.json", "Error")

      expect(backup_report).not_to respond_to(:errors)
      expect(backup_report).to receive(:failed).at_least(:once).and_call_original

      expect { described_class.new.perform }.to raise_error(described_class::BackupIncomplete)
    end
  end

  describe "the cron monitor" do
    let(:recurring_yml) { YAML.load_file(Rails.root.join("config", "recurring.yml")) }

    it "declares the crontab the production schedule actually uses" do
      scheduled = recurring_yml.fetch("production").fetch("backup_legislation_artifacts").fetch("schedule")

      expect(described_class::MONITOR_CRONTAB).to eq(scheduled)
    end

    it "sends a max_runtime, which a nil would compact out of the payload" do
      expect(described_class::MONITOR_CONFIG.to_h)
        .to include(max_runtime: described_class::MONITOR_MAX_RUNTIME_MINUTES)
    end
  end
end
