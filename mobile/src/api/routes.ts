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

    bills: () => "/bills",
    pastBillsOfTheMonth: () => "/past_bills_of_the_month",
    bill: (id: number) => `/bills/${id}`,
    billPublicTestimonyLetters: (billId: number) => `/bills/${billId}/public_testimony_letters`,
    billSummaryReports: (billId: number) => `/bills/${billId}/summary_reports`,
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
