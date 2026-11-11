# frozen_string_literal: true

require "rails_helper"

RSpec.describe RegistrationFunnelMetricsService do
  describe "#call" do
    context "when there are no funnel events" do
      it "returns zeros for all steps, empty latency, and zero conversion rate" do
        result = described_class.new(time_range: "30d").call

        expect(result.time_range).to eq("30d")
        expect(result.overall_conversion_rate).to eq(0.0)
        expect(result.steps.size).to eq(7)
        expect(result.steps.first).to include(
          step: "landing",
          label: "Landing Page",
          visitor_count: 0,
          step_conversion_rate: 100.0,
          drop_off_count: 0
        )
        expect(result.latency).to eq(
          sample_count: 0,
          avg_seconds: 0.0,
          median_seconds: 0.0,
          p95_seconds: 0.0,
          min_seconds: 0.0,
          max_seconds: 0.0
        )
        expect(result.attributions).to be_empty
      end
    end

    context "with a realistic multi-visitor funnel" do
      before do
        # Visitor 1: makes it all the way to vote cast
        RegistrationFunnelEvent.create!(visitor_token: "v1", step: :landing, attribution_key: "s:share1", created_at: 2.days.ago)
        RegistrationFunnelEvent.create!(visitor_token: "v1", step: :phone_submitted, attribution_key: "s:share1", created_at: 2.days.ago)
        RegistrationFunnelEvent.create!(visitor_token: "v1", step: :sms_verified, attribution_key: "s:share1", created_at: 2.days.ago)
        RegistrationFunnelEvent.create!(visitor_token: "v1", step: :passkey_enrolled, attribution_key: "s:share1", created_at: 2.days.ago)
        RegistrationFunnelEvent.create!(visitor_token: "v1", step: :address_submitted, attribution_key: "s:share1", created_at: 2.days.ago)
        RegistrationFunnelEvent.create!(
          visitor_token: "v1",
          step: :geocoding_completed,
          attribution_key: "s:share1",
          created_at: 2.days.ago,
          metadata: {"latency_ms" => 1500.0}
        )
        RegistrationFunnelEvent.create!(visitor_token: "v1", step: :first_vote_cast, attribution_key: "s:share1", created_at: 2.days.ago)

        # Visitor 2: drops off after passkey
        RegistrationFunnelEvent.create!(visitor_token: "v2", step: :landing, created_at: 1.day.ago)
        RegistrationFunnelEvent.create!(visitor_token: "v2", step: :phone_submitted, created_at: 1.day.ago)
        RegistrationFunnelEvent.create!(visitor_token: "v2", step: :sms_verified, created_at: 1.day.ago)
        RegistrationFunnelEvent.create!(visitor_token: "v2", step: :passkey_enrolled, created_at: 1.day.ago)

        # Visitor 3: drops off after phone
        RegistrationFunnelEvent.create!(visitor_token: "v3", step: :landing, attribution_key: "invite:inv1", created_at: 1.hour.ago)
        RegistrationFunnelEvent.create!(visitor_token: "v3", step: :phone_submitted, attribution_key: "invite:inv1", created_at: 1.hour.ago)

        # Visitor 4: bounces on landing
        RegistrationFunnelEvent.create!(visitor_token: "v4", step: :landing, created_at: 10.minutes.ago)

        # Visitor 5: outside 24h window (3 days ago)
        RegistrationFunnelEvent.create!(
          visitor_token: "v5",
          step: :geocoding_completed,
          created_at: 3.days.ago,
          metadata: {"latency_ms" => 3500.0}
        )
      end

      it "calculates step counts and step-to-step drop-offs accurately for 7d window" do
        result = described_class.new(time_range: "7d").call

        # landing: 4 (v1, v2, v3, v4)
        # phone_entered: 3 (v1, v2, v3)
        # sms_verified: 2 (v1, v2)
        # passkey_enrolled: 2 (v1, v2)
        # address_submitted: 1 (v1)
        # registration_completed: 2 (v1, v5)
        # first_vote_cast: 1 (v1)

        landing = result.steps.find { |s| s[:step] == "landing" }
        expect(landing[:visitor_count]).to eq(4)

        phone = result.steps.find { |s| s[:step] == "phone_entered" }
        expect(phone[:visitor_count]).to eq(3)
        expect(phone[:step_conversion_rate]).to eq(75.0) # 3 / 4
        expect(phone[:drop_off_count]).to eq(1)

        passkey = result.steps.find { |s| s[:step] == "passkey_enrolled" }
        expect(passkey[:visitor_count]).to eq(2)
        expect(passkey[:step_conversion_rate]).to eq(100.0) # 2 / 2
        expect(passkey[:drop_off_count]).to eq(0)

        address = result.steps.find { |s| s[:step] == "address_submitted" }
        expect(address[:visitor_count]).to eq(1)
        expect(address[:step_conversion_rate]).to eq(50.0) # 1 / 2
        expect(address[:drop_off_count]).to eq(1)

        vote = result.steps.find { |s| s[:step] == "first_vote_cast" }
        expect(vote[:visitor_count]).to eq(1)
        expect(result.overall_conversion_rate).to eq(25.0) # 1 / 4
      end

      it "ranks friction points correctly" do
        result = described_class.new(time_range: "7d").call
        friction = result.friction_points

        expect(friction).not_to be_empty
        # All friction items have rank_by_count and rank_by_rate
        friction.each do |point|
          expect(point[:rank_by_count]).to be_a(Integer)
          expect(point[:rank_by_rate]).to be_a(Integer)
        end
      end

      it "computes attribution breakdown by source" do
        result = described_class.new(time_range: "7d").call
        sources = result.attributions.pluck(:source)

        expect(sources).to include("s:share1", "invite:inv1", "direct")
        share_attr = result.attributions.find { |a| a[:source] == "s:share1" }
        expect(share_attr[:visitors_count]).to eq(1)
        expect(share_attr[:registrations_count]).to eq(1)
        expect(share_attr[:votes_count]).to eq(1)
        expect(share_attr[:conversion_rate]).to eq(100.0)
      end

      it "calculates median and p95 latency percentiles" do
        result = described_class.new(time_range: "7d").call
        latency = result.latency

        expect(latency[:sample_count]).to eq(2)
        # Latencies are 1500ms (1.5s) and 3500ms (3.5s)
        expect(latency[:min_seconds]).to eq(1.5)
        expect(latency[:max_seconds]).to eq(3.5)
        expect(latency[:median_seconds]).to eq(2.5) # average of 1.5 and 3.5
        expect(latency[:p95_seconds]).to eq(3.5)
      end

      it "filters by attribution_key when specified" do
        result = described_class.new(time_range: "7d", attribution_key: "s:share1").call

        landing = result.steps.find { |s| s[:step] == "landing" }
        expect(landing[:visitor_count]).to eq(1)
        expect(result.overall_conversion_rate).to eq(100.0)
      end

      it "filters organic direct traffic when attribution_key is direct" do
        result = described_class.new(time_range: "7d", attribution_key: "direct").call

        # v2 and v4 have nil attribution_key
        landing = result.steps.find { |s| s[:step] == "landing" }
        expect(landing[:visitor_count]).to eq(2)
      end

      it "filters by time_range 24h excluding older events" do
        result = described_class.new(time_range: "24h").call

        # v1 and v5 are 2-3 days ago, excluded from 24h
        vote = result.steps.find { |s| s[:step] == "first_vote_cast" }
        expect(vote[:visitor_count]).to eq(0)
      end

      # @lat: [[registration-funnel-telemetry#Bot traffic classification#Traffic filter on the admin dashboard]]
      context "with bot traffic" do
        before do
          RegistrationFunnelEvent.create!(visitor_token: "bot1", step: :landing, bot: true, created_at: 1.hour.ago)
          RegistrationFunnelEvent.create!(visitor_token: "bot2", step: :landing, bot: true, created_at: 2.hours.ago)
        end

        it "excludes bot visitors by default (traffic: humans)" do
          result = described_class.new(time_range: "7d").call
          landing = result.steps.find { |s| s[:step] == "landing" }

          expect(result.traffic).to eq("humans")
          expect(landing[:visitor_count]).to eq(4)
          expect(result.bot_visitor_count).to eq(2)
        end

        it "isolates bot visitors when traffic is bots" do
          result = described_class.new(time_range: "7d", traffic: "bots").call
          landing = result.steps.find { |s| s[:step] == "landing" }

          expect(result.traffic).to eq("bots")
          expect(landing[:visitor_count]).to eq(2)
        end

        it "includes all visitors when traffic is all" do
          result = described_class.new(time_range: "7d", traffic: "all").call
          landing = result.steps.find { |s| s[:step] == "landing" }

          expect(result.traffic).to eq("all")
          expect(landing[:visitor_count]).to eq(6)
        end
      end

      # @lat: [[registration-funnel-telemetry#Registration funnel metrics and friction ranking]]
      context "with out-of-order steps and duplicate visitor step emissions" do
        it "clamps drop-off for orphan visitors starting mid-funnel and deduplicates repeated step events" do
          RegistrationFunnelEvent.delete_all
          5.times do |i|
            RegistrationFunnelEvent.create!(visitor_token: "orphan-#{i}", step: :address_submitted, created_at: 2.hours.ago)
          end
          3.times do
            RegistrationFunnelEvent.create!(visitor_token: "dup-1", step: :landing, created_at: 1.hour.ago)
          end

          result = described_class.new(time_range: "24h").call
          landing = result.steps.find { |s| s[:step] == "landing" }
          address = result.steps.find { |s| s[:step] == "address_submitted" }

          expect(landing[:visitor_count]).to eq(1)
          expect(address[:visitor_count]).to eq(5)
          expect(address[:drop_off_count]).to eq(0)
          expect(address[:drop_off_rate]).to eq(0.0)
        end
      end
    end
  end
end
