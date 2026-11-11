import { describe, expect, it } from "vitest";
import { freshnessLabel, freshnessTone } from "app/frontend/components/admin/creator/fetched-bills/freshness";

const DAY = 24 * 60 * 60 * 1000;
const ago = (days: number) => new Date(Date.now() - days * DAY).toISOString();

describe("freshnessTone", () => {
    it("returns 'success' for artifacts fetched within 7 days", () => {
        expect(freshnessTone(ago(1))).toBe("success");
        expect(freshnessTone(ago(6))).toBe("success");
    });

    it("returns 'warning' between 7 and 30 days", () => {
        expect(freshnessTone(ago(8))).toBe("warning");
        expect(freshnessTone(ago(29))).toBe("warning");
    });

    it("returns 'danger' past 30 days", () => {
        expect(freshnessTone(ago(31))).toBe("danger");
        expect(freshnessTone(ago(400))).toBe("danger");
    });
});

describe("freshnessLabel", () => {
    it("maps tones to operator-facing labels", () => {
        expect(freshnessLabel("success")).toBe("fresh");
        expect(freshnessLabel("warning")).toBe("stale");
        expect(freshnessLabel("danger")).toBe("very stale");
    });
});
