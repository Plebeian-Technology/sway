# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Mobile API routes contract" do
  routes_source = Rails.root.join("mobile", "src", "api", "routes.ts").read
  routes_object = routes_source[/export const Routes = \{(.*?)\n\} as const;/m, 1].to_s

  sample_values = {"key" => "botm_announcement"}

  route_keys = routes_object.scan(/^\s+(\w+):/).flatten

  # A sample path for each builder that computes its path.
  computed_paths = {
    "adminRegistrationFunnel" => "/admin/registration_funnel?time_range=30d",
    "adminBillSummaryReports" => "/admin/bill_summary_reports?status=open",
    "adminBillCreatorTab" => "/admin/bill_creator/1/summary",
    "adminBillCreatorPipelineRun" => "/admin/bill_creator/1/pipeline?run_id=1",
    "adminBillCreatorActivityLog" => "/admin/bill_creator/1/pipeline?cursor=1",
    "adminBillCreatorPipelinePreview" => "/admin/bill_creator/1/pipeline?selected_stages=fetch&download_missing_assets=0"
  }

  mobile_paths = routes_object.scan(/^\s+(\w+): \([^)]*\) =>\s*["`]([^"`]+)["`],$/)
    .to_h { |key, path| [key, path.to_s.gsub(/\$\{(?:encodeURIComponent\()?(\w+)\)?\}/) { sample_values.fetch($1, "1") }] }
    .merge(computed_paths)

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
    "bills" => %i[get post],
    "pastBillsOfTheMonth" => %i[get],
    "bill" => %i[get patch],
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
    "orgNotificationDefaults" => %i[get patch],
    "admin" => %i[get],
    "adminSharedAddresses" => %i[get],
    "adminUserAddressChanges" => %i[get],
    "adminSystemPrompts" => %i[get],
    "adminLocales" => %i[get],
    "adminLocale" => %i[patch],
    "adminCategories" => %i[get post],
    "adminCategory" => %i[patch delete],
    "adminLlmSettings" => %i[get patch],
    "adminLlmRefreshModels" => %i[post],
    "adminLlmAddModel" => %i[post],
    "adminLlmRemoveModel" => %i[delete],
    "adminRegistrationFunnel" => %i[get],
    "adminPipelineRuns" => %i[get],
    "adminPartnerReports" => %i[get],
    "adminPartnerReport" => %i[get],
    "adminBillSummaryReport" => %i[get patch],
    "adminBillSummaryReports" => %i[get],
    "adminLegislatorVotes" => %i[post],
    "adminOrganizations" => %i[post],
    "adminOrganization" => %i[patch],
    "adminOrganizationBillPosition" => %i[delete],
    "adminDirectUploads" => %i[post],
    "adminBillOfTheMonthSchedule" => %i[patch],
    "adminBillCreatorNew" => %i[get],
    "adminBillCreatorTab" => %i[get],
    "adminBillCreatorPipelineRun" => %i[get],
    "adminBillCreatorActivityLog" => %i[get],
    "adminBillCreatorSummaryRevisions" => %i[get],
    "adminBillCreatorSummarySourceDocuments" => %i[get],
    "adminBillCreatorSummaryPrompt" => %i[get],
    "adminBillCreatorCampaignLetters" => %i[get],
    "adminBillNewsArticles" => %i[post],
    "adminBillNewsArticle" => %i[patch],
    "adminPipelineRunResume" => %i[post],
    "adminPipelineRunRestart" => %i[post],
    "adminPipelineRunCancel" => %i[delete],
    "adminPipelineRunForceFail" => %i[post],
    "adminSweepStalePipelineRuns" => %i[post],
    "adminDeleteOrphanPipelineRuns" => %i[delete],
    "adminSendingServiceDomain" => %i[patch],
    "adminBillCreatorPipelinePreview" => %i[get],
    "adminRunPipeline" => %i[post],
    "billCategories" => %i[post],
    "billCategory" => %i[delete],
    "billPasteSummary" => %i[post],
    "billGenerateSummary" => %i[post],
    "billRestoreSummaryRevision" => %i[post],
    "billRegenerateSummary" => %i[post],
    "billApproveOrgPosition" => %i[post],
    "billSupplementalTestimony" => %i[patch],
    "billTestimonyLetterStance" => %i[patch],
    "billTestimonyCoverageAcknowledgement" => %i[post],
    "billCampaigns" => %i[post],
    "billCampaignLinkOrganization" => %i[post],
    "billRejectCampaignDraft" => %i[post],
    "billRestoreCampaignDraft" => %i[post],
    "billMarkIndividualCampaignDraft" => %i[post],
    "adminBillDraftOrgPosition" => %i[patch]
  }

  inline_onboarding_paths = {
    "/sway_registration" => %i[post]
  }

  it "parses every key of the mobile Routes object" do
    expect(route_keys).not_to be_empty
    expect(mobile_paths.keys).to match_array(route_keys)
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
