# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Mobile API routes contract" do
  routes_source = Rails.root.join("mobile", "src", "api", "routes.ts").read
  routes_object = routes_source[/export const Routes = \{(.*?)\n\} as const;/m, 1].to_s

  sample_values = {"key" => "botm_announcement"}

  key_count = routes_object.scan(/^\s+(\w+):/).size
  mobile_paths = routes_object.scan(/^\s+(\w+): \([^)]*\) => ["`]([^"`]+)["`],$/)
    .to_h { |key, path| [key, path.to_s.gsub(/\$\{(\w+)\}/) { sample_values.fetch($1, "1") }] }

  verbs_by_key = {
    "bootstrap" => %i[get],
    "sessionsChallenge" => %i[post],
    "sessionsDiscoverableChallenge" => %i[post],
    "sessionsCallback" => %i[post],
    "sessionsRevokeAll" => %i[post],
    "registrations" => %i[post],
    "registrationsCallback" => %i[post],
    "addPasskey" => %i[post],
    "addPasskeyCallback" => %i[post],
    "phoneVerification" => %i[post],
    "phoneVerificationVerify" => %i[post],
    "devicePushToken" => %i[patch],
    "deviceDestroy" => %i[delete],
    "notificationPreferences" => %i[get],
    "notificationPreference" => %i[patch],
    "testPush" => %i[post],
    "feed" => %i[get],
    "bills" => %i[get],
    "pastBillsOfTheMonth" => %i[get],
    "bill" => %i[get],
    "billPublicTestimonyLetters" => %i[get],
    "billSummaryReports" => %i[post],
    "legislators" => %i[get],
    "legislator" => %i[get],
    "userLegislators" => %i[post],
    "userVotes" => %i[post],
    "userBillShares" => %i[post],
    "up" => %i[head],
    "userPreferences" => %i[patch],
    "userDelete" => %i[delete],
    "passkeys" => %i[get],
    "memberships" => %i[get],
    "membership" => %i[get],
    "orgPositions" => %i[post],
    "pendingChange" => %i[patch delete],
    "membershipInvites" => %i[post],
    "acceptInvite" => %i[post],
    "declineInvite" => %i[delete],
    "organizationFollows" => %i[post],
    "organizationFollow" => %i[delete],
    "organizationFollowPreferences" => %i[patch],
    "orgNotificationDefaults" => %i[get patch]
  }

  inline_onboarding_paths = {
    "/sway_registration" => %i[post]
  }

  it "parses every key of the mobile Routes object" do
    expect(key_count).to be > 0
    expect(mobile_paths.size).to eq(key_count)
  end

  it "names a verb for every mobile route and no route the app lacks" do
    expect(verbs_by_key.keys).to match_array(mobile_paths.keys)
  end

  mobile_paths.each do |key, path|
    verbs_by_key.fetch(key, []).each do |verb|
      it "recognizes #{verb.upcase} #{path} (#{key})" do
        expect { Rails.application.routes.recognize_path(path, method: verb) }.not_to raise_error
      end
    end
  end

  inline_onboarding_paths.each do |path, verbs|
    verbs.each do |verb|
      it "recognizes #{verb.upcase} #{path} (inline onboarding path)" do
        expect { Rails.application.routes.recognize_path(path, method: verb) }.not_to raise_error
      end
    end
  end
end
