// @lat: [[mobile-admin-area#The tool map]]
import type { AdminStackParamList } from "../../navigation/types";

export const adminToolScreens: Record<string, Exclude<keyof AdminStackParamList, "AdminHub">> = {
    shared_addresses: "AdminSharedAddresses",
    user_address_changes: "AdminUserAddressChanges",
    system_prompts: "AdminSystemPrompts",
    locales: "AdminLocales",
    categories: "AdminCategories",
    llm_settings: "AdminLlmSettings",
    bill_summary_reports: "AdminBillSummaryReports",
    partner_reports: "AdminPartnerReports",
    registration_funnel: "AdminRegistrationFunnel",
    pipeline_runs: "AdminPipelineRuns",
    bill_creator: "AdminBillPicker",
};
