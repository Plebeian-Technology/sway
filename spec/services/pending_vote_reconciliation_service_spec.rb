# frozen_string_literal: true

require "rails_helper"

class PendingVoteMockCookieJar
  attr_reader :encrypted_store, :regular_store

  def initialize
    @encrypted_store = {}
    @regular_store = {}
  end

  def encrypted
    @encrypted_store
  end

  delegate :[], :[]=, to: :@regular_store

  def delete(key)
    @encrypted_store.delete(key)
    @regular_store.delete(key)
  end
end

RSpec.describe PendingVoteReconciliationService, type: :service do
  # @lat: [[low-friction-voting#Reconciliation on registration and sign-in]]
  # @lat: [[low-friction-voting#Cast-vote finality and replay protection]]
  # @lat: [[low-friction-voting#Secret ballot preservation and attribution]]

  include_context "Setup"

  let(:sway_and_user) { setup }
  let(:sway_locale) { sway_and_user.first }
  let(:user) { sway_and_user.last }
  let(:bill) { create(:bill, sway_locale: sway_locale) }

  let(:cookie_jar) { PendingVoteMockCookieJar.new }

  describe ".call" do
    context "when no pending vote cookie exists" do
      it "returns false with :no_pending_vote and leaves votes unchanged" do
        result = described_class.call(user: user, cookies: cookie_jar)

        expect(result[:success]).to be(false)
        expect(result[:reason]).to eq(:no_pending_vote)
        expect(UserVote.where(user: user, bill: bill)).to be_empty
      end
    end

    context "when pending vote contains invalid data" do
      it "returns false with :invalid_data if support is invalid" do
        cookie_jar.encrypted[:sway_pending_vote] = {
          "bill_id" => bill.id,
          "support" => "ABSTAIN"
        }

        result = described_class.call(user: user, cookies: cookie_jar)

        expect(result[:success]).to be(false)
        expect(result[:reason]).to eq(:invalid_data)
        expect(cookie_jar.encrypted[:sway_pending_vote]).to be_nil
        expect(UserVote.where(user: user, bill: bill)).to be_empty
      end

      it "returns false with :invalid_data if bill does not exist" do
        cookie_jar.encrypted[:sway_pending_vote] = {
          "bill_id" => 999_999,
          "support" => "FOR"
        }

        result = described_class.call(user: user, cookies: cookie_jar)

        expect(result[:success]).to be(false)
        expect(result[:reason]).to eq(:invalid_data)
        expect(cookie_jar.encrypted[:sway_pending_vote]).to be_nil
      end

      it "returns false with :bill_inactive and clears cookie if bill is inactive" do
        inactive_bill = create(:bill, :without_session, sway_locale: sway_locale, active: false)
        cookie_jar.encrypted[:sway_pending_vote] = {
          "bill_id" => inactive_bill.id,
          "support" => "FOR"
        }

        result = described_class.call(user: user, cookies: cookie_jar)

        expect(result[:success]).to be(false)
        expect(result[:reason]).to eq(:bill_inactive)
        expect(cookie_jar.encrypted[:sway_pending_vote]).to be_nil
        expect(UserVote.where(user: user, bill: inactive_bill)).to be_empty
      end
    end

    context "when a fresh registration reconciles a valid pending vote" do
      before do
        cookie_jar.encrypted[:sway_pending_vote] = {
          "bill_id" => bill.id,
          "support" => "FOR",
          "nonce" => SecureRandom.hex(16),
          "created_at" => Time.current.iso8601
        }
        cookie_jar[:sway_attribution_key] = "partner:banner:article-123"
      end

      it "creates a verified UserVote, tracks partner attribution, records funnel event, and clears cookie" do
        expect(ArticleEngagementTrackerService).to receive(:track_vote).with(
          bill: bill,
          stance: "FOR",
          attribution_key: "partner:banner:article-123"
        ).and_call_original

        expect {
          result = described_class.call(user: user, cookies: cookie_jar)
          expect(result[:success]).to be(true)
          expect(result[:status]).to eq(:vote_cast)
          expect(result[:bill]).to eq(bill)
        }.to change(UserVote, :count).by(1)

        uv = UserVote.find_by(user: user, bill: bill)
        expect(uv).to be_present
        expect(uv.support).to eq("FOR")

        expect(cookie_jar.encrypted[:sway_pending_vote]).to be_nil

        # Verify funnel event recorded
        last_funnel_event = user.registration_funnel_events.order(created_at: :desc).first
        expect(last_funnel_event.step).to eq("first_vote_cast")
        expect(last_funnel_event.metadata["bill_id"]).to eq(bill.id)
        expect(last_funnel_event.metadata["support"]).to eq("FOR")
      end
    end

    context "when user already voted on the bill with identical support" do
      before do
        UserVote.create!(user: user, bill: bill, support: "FOR")
        cookie_jar.encrypted[:sway_pending_vote] = {
          "bill_id" => bill.id,
          "support" => "FOR"
        }
      end

      it "returns idempotent success, preserves the existing vote, and clears cookie without creating a new row" do
        expect(ArticleEngagementTrackerService).not_to receive(:track_vote)

        expect {
          result = described_class.call(user: user, cookies: cookie_jar)
          expect(result[:success]).to be(true)
          expect(result[:status]).to eq(:already_voted_same)
          expect(result[:bill]).to eq(bill)
        }.not_to change(UserVote, :count)

        expect(cookie_jar.encrypted[:sway_pending_vote]).to be_nil
        expect(UserVote.find_by(user: user, bill: bill).support).to eq("FOR")
      end
    end

    context "when user already voted on the bill with conflicting support" do
      before do
        UserVote.create!(user: user, bill: bill, support: "FOR")
        cookie_jar.encrypted[:sway_pending_vote] = {
          "bill_id" => bill.id,
          "support" => "AGAINST"
        }
      end

      it "strictly upholds cast-vote finality, leaves original vote unchanged, returns failure, and clears cookie" do
        expect(ArticleEngagementTrackerService).not_to receive(:track_vote)

        expect {
          result = described_class.call(user: user, cookies: cookie_jar)
          expect(result[:success]).to be(false)
          expect(result[:status]).to eq(:already_voted_different)
          expect(result[:bill]).to eq(bill)
          expect(result[:message]).to eq(UserVotesController::VOTE_ALREADY_RECORDED_MESSAGE)
        }.not_to change(UserVote, :count)

        expect(cookie_jar.encrypted[:sway_pending_vote]).to be_nil
        expect(UserVote.find_by(user: user, bill: bill).support).to eq("FOR")
      end
    end
  end
end
