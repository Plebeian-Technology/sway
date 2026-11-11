// @lat: [[bill-creator-field-display-labels#Why fieldDisplayName falls back to titleize, and why BillCreatorOrganizations never reaches it]]

import { describe, expect, it } from "vitest";

import { AUDIO_FIELD_LABELS } from "app/frontend/components/admin/creator/audioFieldLabels";
import { fieldDisplayName } from "app/frontend/components/admin/creator/fieldDisplayName";

describe("fieldDisplayName", () => {
    // @lat: [[bill-creator-field-display-labels#fieldDisplayName.test.ts notes]]
    it.each([
        ["legislator_id", "Legislator Sponsor"],
        ["chamber", "Chamber"],
        ["status", "Bill Status"],
        ["introduced_date_time_utc", "Introduced On"],
        ["house_roll_call_vote_number", "House Vote Roll Call Number"],
        // @lat: [[bill-creator-field-display-labels#fieldDisplayName.test.ts notes]]
        ["audio_bucket_path", AUDIO_FIELD_LABELS.audio_bucket_path],
        ["audio_by_line", AUDIO_FIELD_LABELS.audio_by_line],
    ])("gives %s the form's own label", (name, label) => {
        expect(fieldDisplayName(name)).toBe(label);
    });

    it("prints no raw column name for any field on the form", () => {
        for (const name of ["legislator_id", "introduced_date_time_utc", "house_roll_call_vote_number"]) {
            expect(fieldDisplayName(name)).not.toMatch(/_/);
        }
    });

    // @lat: [[bill-creator-field-display-labels#fieldDisplayName.test.ts notes]]
    it("splits an unknown name on the underscore instead of leaving it as one word", () => {
        expect(fieldDisplayName("organization_position_summary")).toBe("Organization Position Summary");
    });

    it("answers with an empty string for an empty name", () => {
        expect(fieldDisplayName("")).toBe("");
    });
});
