# frozen_string_literal: true

require "rails_helper"

# @lat: [[flash-error-key-hygiene-lint#Why flash(:error) fails the build]]
RSpec.describe "flash key hygiene" do
  it "no controller uses the flash[:error] key (toaster reads notice/alert only)" do
    offenders =
      Rails.root.glob("app/controllers/**/*.rb").select do |path|
        File.read(path).match?(/flash\[\s*:error\s*\]/)
      end

    relative = offenders.map { |p| Pathname.new(p).relative_path_from(Rails.root).to_s }

    expect(offenders).to be_empty,
      "flash[:error] is dropped by app/frontend/sway_utils/flashToasts.ts " \
      "(reads only :notice/:alert). Use flash[:alert] instead. Offenders: #{relative.join(", ")}"
  end
end
