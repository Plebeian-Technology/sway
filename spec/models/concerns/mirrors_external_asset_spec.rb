# frozen_string_literal: true

require "rails_helper"
require "rake"

# @lat: [[sway-google-cloud-storage#A stored file name is not an address]]
RSpec.describe MirrorsExternalAsset do
  # Created before the block, so only the update below is counted. Building one
  # also builds a locale, whose hostless factory icon URL is treated as internal.
  let!(:organization) { create(:organization, icon_url: nil) }

  it "does not queue a copy when a jurisdiction icon URL changes" do
    sway_locale = create(:sway_locale, icon_url: nil)

    # @lat: [[sway-google-cloud-storage#Only consumers of mirrored assets declare the callback]]
    expect { sway_locale.update!(icon_url: "https://example.org/icon.svg") }
      .not_to have_enqueued_job(MirrorExternalAssetJob)
  end

  it "copies a picture that really is hosted somewhere else" do
    expect { organization.update!(icon_url: "https://baltimorecity.gov/logo.png") }
      .to have_enqueued_job(MirrorExternalAssetJob).exactly(1).times
  end

  it "queues a portrait copy when a legislator's outside photo URL changes" do
    legislator = create(:legislator, photo_url: nil)

    # @lat: [[sway-google-cloud-storage#Only consumers of mirrored assets declare the callback]]
    expect {
      legislator.update!(photo_url: "https://example.org/portrait.png")
    }.to have_enqueued_job(MirrorExternalAssetJob).with(
      record_class_name: "Legislator",
      record_id: legislator.id,
      attachment_name: "photo",
      url_column: "photo_url"
    )
  end

  # 35 production organizations hold one of these.
  it "leaves a storage bucket key alone" do
    expect { organization.update!(icon_url: "baltimore-maryland-united_states/MCB-171865.jpg") }
      .not_to have_enqueued_job(MirrorExternalAssetJob)
  end

  it "leaves an app path alone" do
    expect { organization.update!(icon_url: "/images/sway-us-light.png") }
      .not_to have_enqueued_job(MirrorExternalAssetJob)
  end

  # A leading '//' carries a host, so it is still somewhere else.
  it "still copies a picture named without a scheme" do
    expect { organization.update!(icon_url: "//example.org/logo.png") }
      .to have_enqueued_job(MirrorExternalAssetJob).exactly(1).times
  end

  it "leaves an address already on our own site alone" do
    expect { organization.update!(icon_url: "https://sway.vote/images/logo.png") }
      .not_to have_enqueued_job(MirrorExternalAssetJob)
  end

  it "leaves an address on one of our own subdomains alone" do
    expect { organization.update!(icon_url: "https://app.sway.vote/x.png") }
      .not_to have_enqueued_job(MirrorExternalAssetJob)
  end

  it "copies a picture from a lookalike host that only ends in our name" do
    expect { organization.update!(icon_url: "https://evilsway.vote/x.png") }
      .to have_enqueued_job(MirrorExternalAssetJob).exactly(1).times
  end

  describe "#internal_asset_url?" do
    it "matches our apex and subdomains but not a lookalike host" do
      expect(organization.send(:internal_asset_url?, "https://sway.vote/x.png")).to be(true)
      expect(organization.send(:internal_asset_url?, "https://app.sway.vote/x.png")).to be(true)
      expect(organization.send(:internal_asset_url?, "https://evilsway.vote/x.png")).to be(false)
      expect(organization.send(:internal_asset_url?, "https://notsway.vote/x.png")).to be(false)
    end
  end

  describe "sway:assets:mirror_external_assets" do
    before(:all) do
      Rails.application.load_tasks unless Rake::Task.task_defined?("sway:assets:mirror_external_assets")
    end

    before { Rake::Task["sway:assets:mirror_external_assets"].reenable }

    # @lat: [[sway-google-cloud-storage#Only consumers of mirrored assets declare the callback]]
    it "runs over organizations and legislators without scanning jurisdictions" do
      empty_scope = double(find_each: nil)
      expect(Organization).to receive(:all).and_return(empty_scope)
      expect(Legislator).to receive(:all).and_return(empty_scope)
      expect(SwayLocale).not_to receive(:all)

      expect { Rake::Task["sway:assets:mirror_external_assets"].invoke }.not_to raise_error
    end
  end
end
