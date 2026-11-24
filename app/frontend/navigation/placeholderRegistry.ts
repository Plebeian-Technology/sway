// @lat: [[navigation-placeholder-tracer#Why placeholderRegistry.ts imports no page component]]

export type TShapeKey =
    | "home"
    | "list"
    | "detail"
    | "form"
    | "document"
    | "dashboard"
    | "settings"
    | "creator"
    | "generic";

export interface IPlaceholderEntry {
    shape: TShapeKey;
    pageName: string;
}

export const GENERIC_ENTRY: IPlaceholderEntry = { shape: "generic", pageName: "page" };

interface IRegistryEntry {
    test: (pathname: string) => boolean;
    shape: TShapeKey;
    pageName: string;
}

const exact =
    (path: string): ((pathname: string) => boolean) =>
    (pathname) =>
        pathname === path;

const PLACEHOLDER_ENTRIES: IRegistryEntry[] = [
    { test: exact("/"), shape: "home", pageName: "Home" },
    { test: exact("/feed"), shape: "list", pageName: "Feed" },
    { test: exact("/bills"), shape: "list", pageName: "All Bills" },
    { test: exact("/past_bills_of_the_month"), shape: "list", pageName: "Past Bills of the Month" },
    { test: (pathname) => /^\/bills\/[^/]+$/.test(pathname), shape: "detail", pageName: "Bill" },
    { test: exact("/bill_of_the_month"), shape: "detail", pageName: "Bill of the Month" },
    { test: exact("/legislators"), shape: "list", pageName: "Representatives" },
    { test: (pathname) => /^\/legislators\/[^/]+$/.test(pathname), shape: "detail", pageName: "Representative" },
    { test: exact("/influence"), shape: "dashboard", pageName: "Your Sway" },
    { test: exact("/notifications"), shape: "list", pageName: "Notifications" },
    { test: exact("/api_keys"), shape: "list", pageName: "API keys" },
    { test: exact("/sway_registration"), shape: "form", pageName: "Registration" },
    { test: exact("/version"), shape: "document", pageName: "Version" },
    { test: exact("/licenses"), shape: "document", pageName: "Licenses" },
    { test: exact("/public/organizations"), shape: "list", pageName: "Organizations" },
    {
        test: (pathname) => /^\/public\/organizations\/[^/]+$/.test(pathname),
        shape: "detail",
        pageName: "Organization",
    },
    { test: exact("/users/organization_memberships"), shape: "list", pageName: "Your organizations" },
    { test: exact("/users/passkeys"), shape: "list", pageName: "Passkeys" },
    { test: exact("/profile"), shape: "list", pageName: "Profile" },
    {
        test: (pathname) => /^\/organizations\/[^/]+\/memberships\/[^/]+$/.test(pathname),
        shape: "detail",
        pageName: "Organization membership",
    },
    {
        test: (pathname) => /^\/organizations\/[^/]+\/positions\/new$/.test(pathname),
        shape: "form",
        pageName: "New position",
    },
    {
        test: (pathname) => /^\/organizations\/[^/]+\/membership_invites\/[^/]+\/confirm_accept$/.test(pathname),
        shape: "form",
        pageName: "Organization invite",
    },
    { test: exact("/admin"), shape: "dashboard", pageName: "Admin" },
    { test: exact("/admin/locales"), shape: "settings", pageName: "Locales" },
    { test: exact("/admin/llm_settings"), shape: "settings", pageName: "Model settings" },
    { test: exact("/admin/shared_addresses"), shape: "list", pageName: "Shared addresses" },
    { test: exact("/admin/user_address_changes"), shape: "list", pageName: "Address changes" },
    { test: exact("/admin/categories"), shape: "settings", pageName: "Categories" },
    { test: exact("/admin/bill_summary_reports"), shape: "list", pageName: "Bill summary reports" },
    { test: exact("/admin/partner_reports"), shape: "dashboard", pageName: "Partner reports" },
    { test: exact("/admin/registration_funnel"), shape: "dashboard", pageName: "Registration funnel" },
    { test: exact("/admin/system_prompts"), shape: "document", pageName: "System prompts" },
    { test: exact("/admin/bill_creator/new"), shape: "creator", pageName: "Bill Creator" },
    {
        test: (pathname) => /^\/admin\/bill_creator\/[^/]+\/(creator|schedule|pipeline|summary)$/.test(pathname),
        shape: "creator",
        pageName: "Bill Creator",
    },
    { test: exact("/pipeline_runs"), shape: "list", pageName: "Pipeline runs" },
];

const normalizeTrailingSlash = (pathname: string): string =>
    pathname.length > 1 && pathname.endsWith("/") ? pathname.slice(0, -1) : pathname;

export const resolvePlaceholder = (pathname: string): IPlaceholderEntry => {
    const normalized = normalizeTrailingSlash(pathname);
    const entry = PLACEHOLDER_ENTRIES.find((candidate) => candidate.test(normalized));
    return entry ? { shape: entry.shape, pageName: entry.pageName } : GENERIC_ENTRY;
};
