import { readFileSync } from "fs";
import { describe, expect, it } from "vitest";

import { localeLabelFor } from "app/frontend/sway_utils/locales";

// @lat: [[organization-locale-label-design#Why organizationLocaleLabelWiring.test.tsx checks the call sites, not just the helper]]
const CALL_SITES = ["app/frontend/pages/Organization.tsx", "app/frontend/pages/Organizations.tsx"] as const;

const VIEWER_LOCALES = [
    {
        id: 7,
        name: "baltimore-maryland-united_states",
        city: "baltimore",
        region: "maryland",
        country: "united_states",
    },
] as never[];

describe("localeLabelFor — what the organization slug is for", () => {
    it("falls back to the organization's own slug for an out-of-locale org", () => {
        expect(localeLabelFor(VIEWER_LOCALES, 99, "congress-congress-united_states")).toBeTruthy();
    });

    // The regression, spelled out: the same call without the slug is what
    // either page reverted to the 2-argument form produces.
    it("renders nothing for that org when the slug is not passed", () => {
        expect(localeLabelFor(VIEWER_LOCALES, 99)).toBeUndefined();
    });

    it("prefers the viewer's locale name over the slug when the org is in-locale", () => {
        const label = localeLabelFor(VIEWER_LOCALES, 7, "congress-congress-united_states");

        expect(label).toBeTruthy();
        expect(label?.toLowerCase()).toContain("baltimore");
    });
});

describe("localeLabelFor call sites still pass the organization's slug", () => {
    it.each(CALL_SITES)("%s passes sway_locale_slug", (file) => {
        const source = readFileSync(file, "utf-8");
        const calls = source.match(/localeLabelFor\((?:[^()]|\([^()]*\))*\)/gs) ?? [];

        expect(calls.length, `expected a localeLabelFor call in ${file}`).toBeGreaterThan(0);

        for (const call of calls) {
            expect(call, `${file} calls localeLabelFor without the organization's own slug`).toContain(
                "sway_locale_slug",
            );
        }
    });
});

describe("usePoll call sites pause polling when browser tabs are hidden", () => {
    it.each(CALL_SITES)("%s invokes usePoll with { background: 'pause' }", (file) => {
        const source = readFileSync(file, "utf-8");
        expect(source).toMatch(
            /usePoll\(\s*15000\s*,\s*\{\s*only:\s*POLLING_PROPS\s*\}\s*,\s*\{\s*background:\s*["']pause["']\s*\}\s*\)/,
        );
    });
});
