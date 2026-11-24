# frozen_string_literal: true

# @lat: [[voter-privacy-threshold#Specs that are not about the minimum]]
RSpec.shared_context "with a voter minimum of one" do
  before { stub_const("VoteComparisonPrivacy::MINIMUM_VOTERS", 1) }
end
