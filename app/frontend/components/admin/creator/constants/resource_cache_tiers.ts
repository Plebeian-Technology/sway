import { ResourceCacheTier } from "app/frontend/types/bill_creator";

// @lat: [[per-bill-grid-virtualization#Why ResourceCachePanel indexes mirrors by tier]]
export const TIER_ORDER: readonly ResourceCacheTier[] = [
    "pdf",
    "extracted_text",
    "parsed_sections",
    "diff",
    "summary",
] as const;

export const TIER_LABELS: Record<ResourceCacheTier, string> = {
    pdf: "PDF",
    extracted_text: "Extracted Text",
    parsed_sections: "Parsed Sections",
    diff: "Diff",
    summary: "Summary",
};
