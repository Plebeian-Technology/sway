// @lat: [[paste-summary-schema-example#Test notes]]

import { describe, expect, it } from "vitest";
import { PASTE_SUMMARY_SCHEMA_EXAMPLE } from "app/frontend/components/admin/creator/llm-summary/pasteSummarySchemaExample";

describe("PASTE_SUMMARY_SCHEMA_EXAMPLE", () => {
    const parsed = JSON.parse(PASTE_SUMMARY_SCHEMA_EXAMPLE) as Record<string, unknown>;

    it("does not advertise draft_org_positions", () => {
        expect(PASTE_SUMMARY_SCHEMA_EXAMPLE).not.toContain("draft_org_positions");
        expect(Object.keys(parsed)).not.toContain("draft_org_positions");
    });

    // @lat: [[paste-summary-schema-example#Test notes]]
    it("shows only keys config/schemas/bill_summary.json accepts, including the required one", () => {
        expect(Object.keys(parsed).sort()).toEqual([
            "categories",
            "cited_section_keys",
            "full_breakdown_markdown",
            "news_usage",
            "source_uses",
            "summary_markdown",
        ]);
    });

    it("stays within the schema's 3-category maximum", () => {
        expect((parsed.categories as string[]).length).toBeLessThanOrEqual(3);
    });
});
