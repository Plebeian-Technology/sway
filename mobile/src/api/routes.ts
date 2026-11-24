export const Routes = {
    bootstrap: () => "/api/v1/bootstrap",

    // @lat: [[passkey-only-sms-bootstrap#Why sign-in accepts only a passkey]]
    sessionsChallenge: () => "/api/v1/sessions/challenge",
    // @lat: [[identity-and-access#The sign-in challenge says which ceremony to run#Mobile passkey ceremonies]]
    sessionsDiscoverableChallenge: () => "/api/v1/sessions/discoverable_challenge",
    sessionsCallback: () => "/api/v1/sessions/callback",
    sessionsRevokeAll: () => "/api/v1/sessions/revoke_all",

    registrations: () => "/api/v1/registrations",
    registrationsCallback: () => "/api/v1/registrations/callback",

    // @lat: [[identity-and-access#The admin gate is a lint rule#Adding a passkey re-verifies by SMS first]]
    addPasskey: () => "/api/v1/passkeys",
    addPasskeyCallback: () => "/api/v1/passkeys/callback",

    phoneVerification: () => "/api/v1/phone_verification",
    phoneVerificationVerify: () => "/api/v1/phone_verification/verify",

    devicePushToken: () => "/api/v1/devices/push_token",
    deviceDestroy: (id: number) => `/api/v1/devices/${id}`,

    notificationPreferences: () => "/api/v1/notification_preferences",
    notificationPreference: (key: string) => `/api/v1/notification_preferences/${key}`,

    testPush: () => "/api/v1/notifications/test_push",

    feed: () => "/feed",

    admin: () => "/admin",
    adminSharedAddresses: () => "/admin/shared_addresses",
    adminUserAddressChanges: () => "/admin/user_address_changes",
    adminSystemPrompts: () => "/admin/system_prompts",
    adminLocales: () => "/admin/locales",
    adminLocale: (id: number) => `/admin/locales/${id}`,
    adminCategories: () => "/admin/categories",
    adminCategory: (id: number) => `/admin/categories/${id}`,
    adminLlmSettings: () => "/admin/llm_settings",
    adminLlmRefreshModels: () => "/admin/llm_settings/refresh_models",
    adminLlmAddModel: () => "/admin/llm_settings/add_model",
    adminLlmRemoveModel: (modelId: string) =>
        `/admin/llm_settings/remove_model?model_id=${encodeURIComponent(modelId)}`,

    adminRegistrationFunnel: (timeRange: string, traffic: string, attributionKey: string | null) =>
        `/admin/registration_funnel?time_range=${timeRange}` +
        (attributionKey === null ? "" : `&attribution_key=${encodeURIComponent(attributionKey)}`) +
        (traffic === "humans" ? "" : `&traffic=${traffic}`),
    adminPipelineRuns: () => "/pipeline_runs",
    adminPartnerReports: () => "/admin/partner_reports",
    adminPartnerReport: (partnerSlug: string) => `/admin/partner_reports/${encodeURIComponent(partnerSlug)}`,
    adminBillSummaryReport: (id: number) => `/admin/bill_summary_reports/${id}`,
    adminBillSummaryReports: (status: string, localeId: number | null) =>
        `/admin/bill_summary_reports?status=${status}${localeId === null ? "" : `&locale_id=${localeId}`}`,
    adminLegislatorVotes: () => "/legislator_votes",
    adminOrganizations: (tab: string) => `/organizations?bill_creator_tab=${encodeURIComponent(tab)}`,
    adminOrganization: (id: number) => `/organizations/${id}`,
    adminOrganizationBillPosition: (id: number, tab: string) =>
        `/organization_bill_positions/${id}?bill_creator_tab=${encodeURIComponent(tab)}`,
    adminDirectUploads: () => "/rails/active_storage/direct_uploads",
    adminBillOfTheMonthSchedule: (billId: number) => `/bill_of_the_month_schedule/${billId}`,
    adminBillCreatorNew: () => "/admin/bill_creator/new",
    adminBillCreatorTab: (billId: number | null, tab: string, query: Record<string, string | number> = {}) => {
        const extra = Object.entries(query).map(([key, value]) => `${key}=${encodeURIComponent(value)}`);
        return billId === null
            ? [`/admin/bill_creator/new?bill_creator_tab=${tab}`, ...extra].join("&")
            : `/admin/bill_creator/${billId}/${tab}` + (extra.length > 0 ? `?${extra.join("&")}` : "");
    },
    adminBillCreatorPipelineRun: (billId: number | null, runId: number) =>
        billId === null
            ? `/admin/bill_creator/new?bill_creator_tab=pipeline&run_id=${runId}`
            : `/admin/bill_creator/${billId}/pipeline?run_id=${runId}`,
    adminBillCreatorActivityLog: (billId: number | null, cursor: string) =>
        (billId === null
            ? "/admin/bill_creator/new?bill_creator_tab=pipeline&"
            : `/admin/bill_creator/${billId}/pipeline?`) + `cursor=${encodeURIComponent(cursor)}`,
    adminBillCreatorSummaryRevisions: (billId: number) => `/admin/bill_creator/${billId}/summary?summary_revisions=1`,
    adminBillCreatorSummarySourceDocuments: (billId: number) =>
        `/admin/bill_creator/${billId}/summary?summary_source_documents=1`,
    adminBillCreatorSummaryPrompt: (billId: number) => `/admin/bill_creator/${billId}/summary?summary_prompt=1`,
    adminBillNewsArticles: (billId: number) => `/admin/bills/${billId}/news_articles`,
    adminBillNewsArticle: (billId: number, id: number) => `/admin/bills/${billId}/news_articles/${id}`,
    adminPipelineRunResume: (runId: number) => `/bills/legislation_pipeline_runs/${runId}/resume`,
    adminPipelineRunRestart: (runId: number) => `/bills/legislation_pipeline_runs/${runId}/restart`,
    adminPipelineRunCancel: (runId: number) => `/bills/legislation_pipeline_runs/${runId}`,
    adminPipelineRunForceFail: (runId: number) => `/pipeline_runs/${runId}/force_fail`,
    adminSweepStalePipelineRuns: () => "/bills/sweep_stale_pipeline_runs",
    adminDeleteOrphanPipelineRuns: () => "/pipeline_runs/orphans",
    adminSendingServiceDomain: (domainId: number) => `/sending_service_domains/${domainId}`,
    adminBillCreatorPipelinePreview: (billId: number | null, stages: string[], downloadMissingAssets: boolean) =>
        (billId === null
            ? "/admin/bill_creator/new?bill_creator_tab=pipeline&"
            : `/admin/bill_creator/${billId}/pipeline?`) +
        `selected_stages=${encodeURIComponent(stages.join(","))}&download_missing_assets=${downloadMissingAssets ? "1" : "0"}`,
    adminRunPipeline: () => "/bills/run_pipeline",

    bills: () => "/bills",
    pastBillsOfTheMonth: () => "/past_bills_of_the_month",
    bill: (id: number) => `/bills/${id}`,
    billPublicTestimonyLetters: (billId: number) => `/bills/${billId}/public_testimony_letters`,
    billSummaryReports: (billId: number) => `/bills/${billId}/summary_reports`,
    billCategories: (billId: number) => `/bills/${billId}/categories`,
    billCategory: (billId: number, categoryId: number) => `/bills/${billId}/categories/${categoryId}`,
    billPasteSummary: (billId: number) => `/bills/${billId}/paste_summary`,
    billGenerateSummary: (billId: number) => `/bills/${billId}/generate_summary`,
    billRestoreSummaryRevision: (billId: number) => `/bills/${billId}/restore_summary_revision`,
    billRegenerateSummary: (billId: number) => `/bills/${billId}/regenerate_summary`,
    billApproveOrgPosition: (billId: number) => `/bills/${billId}/approve_org_position`,
    adminBillDraftOrgPosition: (billId: number, index: number) => `/bill_draft_org_positions/${billId}-${index}`,
    legislators: () => "/legislators",
    legislator: (id: number) => `/legislators/${id}`,
    userLegislators: () => "/user_legislators",
    userVotes: () => "/user_votes",
    userBillShares: () => "/user_bill_shares",

    up: () => "/up",

    userPreferences: () => "/users/preferences",
    userDelete: (id: number) => `/users/${id}`,
    passkeys: () => "/users/passkeys",

    memberships: () => "/users/organization_memberships",
    membership: (orgId: number, id: number) => `/organizations/${orgId}/memberships/${id}`,

    orgPositions: (orgId: number) => `/organizations/${orgId}/positions`,
    pendingChange: (orgId: number, id: number) => `/organizations/${orgId}/position_changes/${id}`,
    membershipInvites: (orgId: number) => `/organizations/${orgId}/membership_invites`,

    acceptInvite: (orgId: number, id: number) => `/organizations/${orgId}/membership_invites/${id}/accept`,
    declineInvite: (orgId: number, id: number) => `/organizations/${orgId}/memberships/${id}`,

    organizationFollows: () => "/organization_follows",
    organizationFollow: (id: number) => `/organization_follows/${id}`,
    organizationFollowPreferences: (id: number) => `/organization_follows/${id}/preferences`,
    orgNotificationDefaults: () => "/api/v1/notification_preferences/org_defaults",
} as const;

export type RouteBuilder = typeof Routes;
