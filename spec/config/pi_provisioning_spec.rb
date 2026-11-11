# frozen_string_literal: true

require "open3"
require "rails_helper"

# @lat: [[raspberry-pi-provisioning#Getting a Raspberry Pi ready to serve Sway]]
RSpec.describe "Raspberry Pi provisioning scripts" do
  it "keeps scripts/provision-pi.sh and scripts/verify-pi.sh executable and free of hardcoded hosts" do
    ["provision-pi.sh", "verify-pi.sh"].each do |name|
      path = Rails.root.join("scripts", name)
      expect(path.executable?).to be(true)

      lines = path.read.lines(chomp: true)
      uncommented =
        lines
          .reject { |line| line.match?(/\A\s*#/) }
          .map { |line| line.sub(/\s+#.*\z/, "") }
          .join

      expect(uncommented).not_to match(/\b(?:\d{1,3}\.){3}\d{1,3}\b/)
      expect(uncommented).not_to match(/\.local\b/i)
    end
  end

  it "plans the pdf extractor packages and systemd units during provision-pi.sh check" do
    script_path = Rails.root.join("scripts", "provision-pi.sh").to_s
    env = {
      "SWAY_PI_DISK_UUID" => "00000000-0000-0000-0000-000000000000",
      "SWAY_PI_MOUNT" => "/mnt/ssd",
      "SWAY_PI_STORAGE_DIR" => "/mnt/ssd/sway/storage",
      "SWAY_PI_REGISTRY" => "registry.example.test:5000"
    }

    stdout, stderr, status = Open3.capture3(env, script_path, "check")

    expect(status.exitstatus).to eq(0), "expected check to exit 0, got #{status.exitstatus}: #{stderr}"
    expect(stdout).to include("== pdf extractor ==")
    expect(stdout).to include("mupdf-tools")
    expect(stdout).to include("tesseract-ocr")
    expect(stdout).to include("tesseract-ocr-eng")
    expect(stdout).to include("sway-pdf-extractor.service")
    expect(stdout).to include("sway-pdf-extractor.path")
  end

  it "defines the standalone pdf-extractor subcommand in scripts/provision-pi.sh" do
    provision_script = Rails.root.join("scripts", "provision-pi.sh").read

    expect(provision_script).to match(/pdf-extractor\)\s+\[\[\s*"\$\(id -u\)"\s*-eq\s*0\s*\]\]\s*\|\|\s*fail\s+"pdf-extractor needs root: sudo \$0 pdf-extractor"\s+need SWAY_PI_STORAGE_DIR\s+APPLY=1\s+ensure_pdf_extractor\s+;;/m)
  end

  # @lat: [[raspberry-pi-provisioning#Why the host PDF extractor runs as the container's account and restarts from a path watch]]
  it "configures sway-pdf-extractor systemd service, path unit, and home directory traversal in scripts/provision-pi.sh" do
    provision_script = Rails.root.join("scripts", "provision-pi.sh").read

    expect(provision_script).to include("/etc/systemd/system/sway-pdf-extractor.service")
    expect(provision_script).to include("RequiresMountsFor=${MOUNT_POINT:-$STORAGE_DIR}")
    expect(provision_script).to include("ConditionPathExists=$home/bin/sway-pdf-extractor")
    expect(provision_script).to include("User=${CONTAINER_UID}")
    expect(provision_script).to include("Group=${CONTAINER_GID}")
    expect(provision_script).to include('Environment="TESSDATA_PREFIX=/usr/share/tesseract-ocr/5/tessdata"')
    expect(provision_script).to include('Environment="OMP_THREAD_LIMIT=1"')
    expect(provision_script).to include('Environment="PDF_EXTRACTOR_ALLOWED_ROOT=$STORAGE_DIR"')
    expect(provision_script).to include('Environment="PDF_EXTRACTOR_CONTAINER_ROOT=/rails/storage"')
    expect(provision_script).to include('Environment="PDF_EXTRACTOR_PORT=8085"')
    expect(provision_script).to include('Environment="PDF_EXTRACTOR_CONCURRENCY=1"')
    expect(provision_script).to include('chmod 0755 "$home"')
    expect(provision_script).to include('install -d -m 0755 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$home/bin"')
    expect(provision_script).to include("/etc/systemd/system/sway-pdf-extractor.path")
    expect(provision_script).to include("PathChanged=$home/bin/sway-pdf-extractor")
    expect(provision_script).to include("/etc/systemd/system/sway-pdf-extractor-restart.service")
    expect(provision_script).to include("StartLimitIntervalSec=0")
    expect(provision_script).to include("systemctl reset-failed sway-pdf-extractor.path sway-pdf-extractor-restart.service sway-pdf-extractor.service")
  end

  it "verifies the pdf extractor binaries, traineddata, and systemd units in scripts/verify-pi.sh" do
    verify_script = Rails.root.join("scripts", "verify-pi.sh").read

    expect(verify_script).to include('step "the pdf extractor"')
    expect(verify_script).to include("mutool")
    expect(verify_script).to include("tesseract")
    expect(verify_script).to include("/usr/share/tesseract-ocr/5/tessdata/eng.traineddata")
    expect(verify_script).to include("/etc/systemd/system/sway-pdf-extractor.service")
    expect(verify_script).to include("/etc/systemd/system/sway-pdf-extractor.path")
  end
end
