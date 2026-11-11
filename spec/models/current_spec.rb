# frozen_string_literal: true

require "rails_helper"

RSpec.describe Current, type: :model do
  it "sets Current.request inside a request context" do
    # Do by hand what ApplicationController's before_action does
    fake_request = instance_double(ActionDispatch::Request)
    Current.request = fake_request
    expect(Current.request).to eq(fake_request)
  end

  it "returns nil for Current.request when not set" do
    expect(Current.request).to be_nil
  end

  # A before(:each) hook calls Current.reset, so the previous example's fake value
  # must not leak into this one.
  it "does not leak Current.request state from a previous example" do
    expect(Current.request).to be_nil
  end
end
