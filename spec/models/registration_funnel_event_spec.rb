# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: registration_funnel_events
# Database name: primary
#
#  id              :integer          not null, primary key
#  attribution_key :string(100)
#  bot             :boolean          default(FALSE), not null
#  metadata        :json             not null
#  step            :integer          not null
#  visitor_token   :string(64)       not null
#  created_at      :datetime         not null
#  user_id         :integer
#
# Indexes
#
#  index_registration_funnel_events_on_attribution_and_created_at  (attribution_key,created_at)
#  index_registration_funnel_events_on_bot_step_created_at         (bot,step,created_at)
#  index_registration_funnel_events_on_step_and_created_at         (step,created_at)
#  index_registration_funnel_events_on_user_id                     (user_id)
#  index_registration_funnel_events_on_visitor_token               (visitor_token)
#
# Foreign Keys
#
#  user_id  (user_id => users.id) ON DELETE => nullify
#
RSpec.describe RegistrationFunnelEvent, type: :model do
  let(:user) { create(:user) }

  describe "validations" do
    it "is valid with visitor_token and valid step" do
      event = described_class.new(visitor_token: "v-token-123", step: :landing)
      expect(event).to be_valid
    end

    it "requires visitor_token" do
      event = described_class.new(visitor_token: nil, step: :landing)
      expect(event).not_to be_valid
      expect(event.errors[:visitor_token]).to be_present
    end

    it "allows associating an optional user" do
      event = described_class.new(visitor_token: "v-token-123", step: :landing, user:)
      expect(event).to be_valid
      expect(event.user).to eq(user)
    end

    it "nullifies user association when user is destroyed" do
      event = described_class.create!(visitor_token: "v-token-123", step: :landing, user:)
      user.destroy!
      expect(event.reload.user_id).to be_nil
    end
  end

  describe "enums and aliases" do
    it "supports landing step" do
      event = described_class.create!(visitor_token: "vt", step: :landing)
      expect(event).to be_landing
    end

    it "maps phone_entered and phone_submitted to same value" do
      event1 = described_class.new(step: :phone_entered)
      event2 = described_class.new(step: :phone_submitted)
      expect(event1.read_attribute_before_type_cast(:step)).to eq(event2.read_attribute_before_type_cast(:step))
    end

    it "maps registration_completed and geocoding_completed to same value" do
      event1 = described_class.new(step: :registration_completed)
      event2 = described_class.new(step: :geocoding_completed)
      expect(event1.read_attribute_before_type_cast(:step)).to eq(event2.read_attribute_before_type_cast(:step))
    end

    it "defines all canonical steps" do
      canonical = described_class::CANONICAL_STEPS
      expect(canonical).to include(
        "landing",
        "phone_submitted",
        "sms_verified",
        "passkey_enrolled",
        "address_submitted",
        "geocoding_completed",
        "first_vote_cast"
      )
    end
  end

  describe "scopes and helpers" do
    let!(:event1) { described_class.create!(visitor_token: "v1", step: :landing, created_at: 2.days.ago) }
    let!(:event2) { described_class.create!(visitor_token: "v2", step: :phone_submitted, created_at: 1.day.ago) }
    let!(:event3) { described_class.create!(visitor_token: "v1", step: :sms_verified, created_at: 1.hour.ago) }

    it "filters by step with for_step" do
      expect(described_class.for_step(:landing)).to contain_exactly(event1)
    end

    it "filters by time window with in_window" do
      expect(described_class.in_window(36.hours.ago..Time.current)).to contain_exactly(event2, event3)
    end

    it "filters by visitor_token" do
      expect(described_class.for_visitor("v1")).to contain_exactly(event1, event3)
    end

    it "extracts latency_ms from metadata" do
      event_with_latency = described_class.new(
        visitor_token: "vt",
        step: :geocoding_completed,
        metadata: {"latency_ms" => 345.6}
      )
      expect(event_with_latency.latency_ms).to eq(345.6)
    end

    it "returns nil latency_ms when not present in metadata" do
      event = described_class.new(visitor_token: "vt", step: :landing, metadata: {})
      expect(event.latency_ms).to be_nil
    end

    it "filters human and bot traffic via scopes" do
      human_event = described_class.create!(visitor_token: "vh", step: :landing, bot: false)
      bot_event = described_class.create!(visitor_token: "vb", step: :landing, bot: true)

      expect(described_class.humans).to include(human_event)
      expect(described_class.humans).not_to include(bot_event)
      expect(described_class.bots).to include(bot_event)
      expect(described_class.bots).not_to include(human_event)
    end
  end

  # @lat: [[registration-funnel-telemetry#Bot traffic classification]]
  describe ".bot_traffic?" do
    it "classifies api users as bot traffic" do
      api_user = create(:user)
      allow(api_user).to receive(:is_sway_api_user?).and_return(true)

      expect(described_class.bot_traffic?(user: api_user)).to be true
    end

    it "classifies normal users as human traffic" do
      normal_user = create(:user)
      allow(normal_user).to receive(:is_sway_api_user?).and_return(false)

      expect(described_class.bot_traffic?(user: normal_user)).to be false
    end

    it "delegates to BotUserAgent when user is nil" do
      expect(described_class.bot_traffic?(user: nil, user_agent: "curl/8.0")).to be true
      expect(described_class.bot_traffic?(user: nil, user_agent: "Mozilla/5.0 (Macintosh)")).to be false
    end
  end

  # @lat: [[registration-funnel-telemetry#Bot traffic classification#Verified users reclassify their visitor token]]
  describe ".mark_visitor_human!" do
    it "reclassifies earlier bot events for the token to human" do
      event1 = described_class.create!(visitor_token: "token-x", step: :landing, bot: true)
      event2 = described_class.create!(visitor_token: "token-other", step: :landing, bot: true)

      described_class.mark_visitor_human!("token-x")

      expect(event1.reload.bot).to be false
      expect(event2.reload.bot).to be true
    end

    it "returns 0 and does not perform updates for nil or blank visitor token" do
      expect(described_class.mark_visitor_human!(nil)).to eq(0)
      expect(described_class.mark_visitor_human!("")).to eq(0)
      expect(described_class.mark_visitor_human!("   ")).to eq(0)
    end
  end
end
