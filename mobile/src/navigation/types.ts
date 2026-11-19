// @lat: [[mobile-tab-navigation-architecture#types.ts: why the route-name types are split per stack]]
export type RootParamList = {
    Auth: undefined;
    Feed: undefined;
    Home: undefined;
    Bills: undefined;
    Legislators: undefined;
    Orgs: undefined;
    Profile: undefined;
    Admin: undefined;
};

// @lat: [[mobile-auth-and-onboarding-flow#AuthStack#types.ts's AuthStackParamList]]
export type AuthStackParamList = {
    Auth: undefined;
    DeviceUnsupported: undefined;
};

// @lat: [[mobile-auth-and-onboarding-flow#OnboardingStack#types.ts's OnboardingStackParamList]]
export type OnboardingStackParamList = {
    AddressOnboarding: undefined;
};

export type AppDrawerParamList = {
    Feed: undefined;
    Home: undefined;
    Bills: undefined;
    Legislators: undefined;
    Orgs: undefined;
    Profile: undefined;
    Admin: undefined;
};

export type FeedStackParamList = {
    FeedList: undefined;
    BillDetail: { id: number };
};

export type HomeStackParamList = {
    BillOfTheMonth: undefined;
    BillDetail: { id: number };
};

export type BillsStackParamList = {
    BillsList: { mode?: "all_bills" | "past_bills_of_the_month" } | undefined;
    PastBillsOfTheMonth?: { mode?: "all_bills" | "past_bills_of_the_month" } | undefined;
    BillDetail: { id: number };
};

export type LegislatorsStackParamList = {
    LegislatorsList: undefined;
    LegislatorDetail: { id: number };
    BillDetail: { id: number };
};

export type OrgsStackParamList = {
    OrgsList: undefined;
    OrgDetail: { id: number };
};

export type ProfileStackParamList = {
    // @lat: [[naming-decisions#Naming decisions#A route name is not a label]]
    ProfileHub: undefined;
    Address: undefined;
    NotificationPrefs: undefined;
    PasskeyManagement: undefined;
    DeleteAccount: undefined;
    MembershipsList: undefined;
    MembershipDetail: { orgId: number; id: number; tab?: string };
};

// @lat: [[mobile-admin-area#The admin stack]]
export type AdminStackParamList = {
    AdminHub: undefined;
    AdminSharedAddresses: undefined;
    AdminUserAddressChanges: undefined;
    AdminSystemPrompts: undefined;
    AdminLocales: undefined;
    AdminCategories: undefined;
    AdminLlmSettings: undefined;
    AdminBillSummaryReports: undefined;
    AdminBillSummaryReport: { id: number };
    AdminPartnerReports: undefined;
    AdminPartnerReport: { partnerSlug: string };
    AdminRegistrationFunnel: undefined;
};
