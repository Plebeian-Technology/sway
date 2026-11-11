import { describe, expect, it } from "vitest";
import { formatEta } from "app/frontend/sway_utils/format_eta";

describe("formatEta", () => {
    it("returns empty string for null", () => expect(formatEta(null)).toBe(""));
    it("returns empty string for undefined", () => expect(formatEta(undefined)).toBe(""));
    it("formats seconds under 60", () => expect(formatEta(45)).toBe("45s"));
    it("formats minutes + seconds", () => expect(formatEta(135)).toBe("2m 15s"));
    it("formats hours + minutes", () => expect(formatEta(3840)).toBe("1h 4m"));
    it("handles exact hour boundary", () => expect(formatEta(3600)).toBe("1h 0m"));
    it("handles exact minute boundary", () => expect(formatEta(60)).toBe("1m 0s"));
    it("handles zero", () => expect(formatEta(0)).toBe("0s"));
});
