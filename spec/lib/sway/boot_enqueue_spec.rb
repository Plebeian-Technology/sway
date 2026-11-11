# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sway::BootEnqueue do
  describe ".web_server_process?" do
    it "is true when Rails::Server is defined" do
      stub_const("Rails::Server", Class.new)

      expect(described_class.web_server_process?).to be(true)
    end

    it "is false when Rails::Server is not defined" do
      hide_const("Rails::Server")

      expect(described_class.web_server_process?).to be(false)
    end
  end
end
