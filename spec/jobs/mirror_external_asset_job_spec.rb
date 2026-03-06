require "rails_helper"

RSpec.describe MirrorExternalAssetJob, type: :job do
  describe "#perform" do
    it "calls mirror service when record exists" do
      organization = create(:organization)

      expect(ExternalAssetMirrorService).to receive(:call).with(
        record: organization,
        attachment_name: "icon",
        url_column: "icon_url",
      )

      described_class.new.perform(
        record_class_name: "Organization",
        record_id: organization.id,
        attachment_name: "icon",
        url_column: "icon_url",
      )
    end

    it "noops when record does not exist" do
      expect(ExternalAssetMirrorService).not_to receive(:call)

      described_class.new.perform(
        record_class_name: "Organization",
        record_id: 0,
        attachment_name: "icon",
        url_column: "icon_url",
      )
    end
  end
end
