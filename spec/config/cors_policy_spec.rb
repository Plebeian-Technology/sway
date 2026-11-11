# frozen_string_literal: true

require "spec_helper"

RSpec.describe "CORS policy" do
  let(:application_rb_path) { File.expand_path("../../config/application.rb", __dir__.to_s) }
  let(:gemfile_path) { File.expand_path("../../Gemfile", __dir__.to_s) }
  let(:gemfile_lock_path) { File.expand_path("../../Gemfile.lock", __dir__.to_s) }

  it "does NOT include rack-cors in the Gemfile" do
    gemfile = File.read(gemfile_path)
    expect(gemfile).not_to match(/^\s*gem\s+["']rack-cors["']/)
  end

  it "does NOT include rack-cors in Gemfile.lock" do
    lock = File.read(gemfile_lock_path)
    expect(lock).not_to match(/^\s*rack-cors\s/)
  end

  # Decision at the code site, reasons in the doc it points at.
  it "states the CORS decision at the code site and its rationale in the linked doc" do
    contents = File.read(application_rb_path)
    expect(contents).to include("@lat: [[content-security-policy#Why CORS is not configured]]")

    lat_doc_path = File.expand_path("../../lat.md/explanation/content-security-policy.md", __dir__.to_s)
    rationale = File.read(lat_doc_path)
    expect(rationale).to include("Rack::Cors")
    expect(rationale).to include("same-origin")
  end
end
