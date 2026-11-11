import { describe, expect, it } from "vitest";
import { formatDateShort } from "app/frontend/sway_utils/datetimes";

describe("formatDateShort", () => {
    it("formats a date as an en-US short numeric date", () => {
        const iso = "2026-07-04T12:00:00Z";
        expect(formatDateShort(iso)).toBe(new Date(iso).toLocaleDateString("en-US"));
    });

    it("returns an empty string for null, undefined, or blank input", () => {
        expect(formatDateShort(null)).toBe("");
        expect(formatDateShort(undefined)).toBe("");
        expect(formatDateShort("")).toBe("");
    });
});
