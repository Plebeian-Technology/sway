# frozen_string_literal: true

require "rails_helper"

# @lat: [[explanation/keyfile-write-directory#Why write_keyfile controls its own disk writes#Creating the directory needs a writable parent]]
RSpec.describe "the directory the production image lets the app write its keyfile into" do
  let(:dockerfile) do
    Rails.root.join("docker", "dockerfiles", "production.alpine.dockerfile").read
  end

  let(:runtime_lines) { dockerfile.each_line.reject { |line| line.match?(/\A\s*#/) } }

  # The directory SwayGoogleCloudStorage writes into, relative to Rails.root —
  # read from the code so moving the keyfile breaks this spec rather than the
  # next deploy.
  let(:keyfile_dir) do
    Pathname.new(SwayGoogleCloudStorage.keyfile_path).dirname.relative_path_from(Rails.root).to_s
  end

  it "reads a keyfile directory under Rails.root" do
    expect(keyfile_dir).not_to start_with(".."),
      "SwayGoogleCloudStorage.keyfile_path left Rails.root, so this spec no longer describes " \
      "anything the image builds"
  end

  it "runs as the rails user, so the write needs an owned directory" do
    expect(runtime_lines.join).to match(/^USER\s+rails/),
      "the production image no longer drops to the rails user — if that is deliberate, delete " \
      "this spec; leaving it passes without checking anything"
  end

  it "creates that directory and gives it to the rails user" do
    dir = Regexp.escape(keyfile_dir)
    created = runtime_lines.any? { |line| line.match?(/mkdir\s+-p\s.*\s#{dir}(\s|$|\\)/) }
    owned = runtime_lines.any? { |line| line.match?(/chown\s+rails:rails\s.*\s#{dir}(\s|$|\\)/) }

    expect(created && owned).to be(true),
      "SwayGoogleCloudStorage writes #{keyfile_dir}/ at boot, but the production image neither " \
      "creates it nor hands it to the rails user. /rails is root-owned, so the Active Storage " \
      "credentials initializer dies with Errno::EACCES and the container never starts."
  end
end
