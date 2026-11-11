import { CONGRESS_SWAY_LOCALE_NAME, isCongressLocale, Locale, toFormattedLocaleName } from "../../src/utils/locale";

describe("mobile locale utils", () => {
    const mockLocale: Locale = {
        id: 1,
        name: "congress-congress-united_states",
        city: "congress",
        region_code: "congress",
        region_name: "congress",
        country: "united_states",
        icon_url: "",
        time_zone: "America/New_York",
        current_session_start_date: "2025-01-03",
    };

    const mockBaltimoreLocale: Locale = {
        id: 2,
        name: "baltimore-maryland-united_states",
        city: "baltimore",
        region_code: "MD",
        region_name: "maryland",
        country: "united_states",
        icon_url: "",
        time_zone: "America/New_York",
        current_session_start_date: "2024-12-05",
    };

    describe("CONGRESS_SWAY_LOCALE_NAME", () => {
        it("pins the literal congress slug", () => {
            expect(CONGRESS_SWAY_LOCALE_NAME).toBe("congress-congress-united_states");
        });
    });

    describe("isCongressLocale", () => {
        it("identifies congress locale from string", () => {
            expect(isCongressLocale("congress-congress-united_states")).toBe(true);
            expect(isCongressLocale("baltimore-maryland-united_states")).toBe(false);
        });

        it("identifies congress locale from Locale object", () => {
            expect(isCongressLocale(mockLocale)).toBe(true);
            expect(isCongressLocale(mockBaltimoreLocale)).toBe(false);
        });

        it("returns false for undefined", () => {
            expect(isCongressLocale(undefined)).toBe(false);
        });
    });

    describe("toFormattedLocaleName", () => {
        it("formats congress locale as U.S. Congress", () => {
            expect(toFormattedLocaleName("congress-congress-united_states")).toBe("U.S. Congress");
        });

        it("formats standard locale with and without country", () => {
            expect(toFormattedLocaleName("baltimore-maryland-united_states", true)).toBe(
                "Baltimore, Maryland, United States",
            );
            expect(toFormattedLocaleName("baltimore-maryland-united_states", false)).toBe("Baltimore, Maryland");
        });

        it("handles empty or undefined input", () => {
            expect(toFormattedLocaleName(undefined)).toBe("");
            expect(toFormattedLocaleName("")).toBe("");
        });
    });
});
