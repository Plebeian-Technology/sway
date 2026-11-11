import { describe, expect, it } from "vitest";
import type { sway } from "sway";
import { isCongressLocale, localeLabelFor } from "app/frontend/sway_utils/locales";

const swayLocale = (id: number, name: string): sway.ISwayLocale => ({ id, name }) as sway.ISwayLocale;

describe("localeLabelFor", () => {
    const locales = [
        swayLocale(1, "baltimore-maryland-united_states"),
        swayLocale(2, "congress-congress-united_states"),
    ];

    it("returns the short (no-country) formatted label for a matching id", () => {
        expect(localeLabelFor(locales, 1)).toBe("Baltimore, Maryland");
    });

    it("returns U.S. Congress for the congress locale", () => {
        expect(localeLabelFor(locales, 2)).toBe("U.S. Congress");
    });

    it("returns undefined when no locale matches the id", () => {
        expect(localeLabelFor(locales, 999)).toBeUndefined();
    });

    // @lat: [[locale-name-is-derived#A locale's name is derived, not stored#Why localeLabelFor takes a fallback slug]]
    describe("for a jurisdiction outside the viewer's own", () => {
        it("falls back to the slug the record carries", () => {
            expect(localeLabelFor(locales, 999, "baltimore")).toBe("Baltimore");
        });

        it("prefers the viewer's locale list when it does have the id", () => {
            expect(localeLabelFor(locales, 1, "somewhere-else")).toBe("Baltimore, Maryland");
        });

        it("still returns undefined when there is no slug either", () => {
            expect(localeLabelFor(locales, 999, null)).toBeUndefined();
            expect(localeLabelFor(locales, 999, "")).toBeUndefined();
        });
    });
});

describe("isCongressLocale", () => {
    it("identifies the congress locale by string or object", () => {
        expect(isCongressLocale("congress-congress-united_states")).toBe(true);
        expect(isCongressLocale(swayLocale(2, "congress-congress-united_states"))).toBe(true);
        expect(isCongressLocale("baltimore-maryland-united_states")).toBe(false);
        expect(isCongressLocale(undefined)).toBe(false);
    });
});
