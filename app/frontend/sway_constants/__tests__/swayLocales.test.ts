import { describe, expect, it } from "vitest";
import {
    CONGRESS_SWAY_LOCALE_NAME,
    ESwayLocaleName,
    VOTING_WEBSITES_BY_SWAY_LOCALE,
} from "app/frontend/sway_constants/swayLocales";
import {
    CONGRESS_SWAY_LOCALE_NAME as RE_EXPORTED_CONGRESS,
    ESwayLocaleName as RE_EXPORTED_ENUM,
    VOTING_WEBSITES_BY_SWAY_LOCALE as RE_EXPORTED_WEBSITES,
} from "app/frontend/sway_constants";

describe("swayLocales constants", () => {
    it("pins the CONGRESS_SWAY_LOCALE_NAME slug literal", () => {
        expect(CONGRESS_SWAY_LOCALE_NAME).toBe("congress-congress-united_states");
        expect(RE_EXPORTED_CONGRESS).toBe("congress-congress-united_states");
    });

    it("pins the ESwayLocaleName enum member slugs", () => {
        expect(ESwayLocaleName.BALTIMORE).toBe("baltimore-maryland-united_states");
        expect(ESwayLocaleName.BALTIMORE_COUNTY).toBe("baltimore_county-maryland-united_states");
        expect(ESwayLocaleName.WASHINGTON_DC).toBe("washington-district_of_columbia-united_states");
        expect(ESwayLocaleName.LOS_ANGELES).toBe("los_angeles-california-united_states");
        expect(ESwayLocaleName.MARYLAND).toBe("maryland-maryland-united_states");
        expect(ESwayLocaleName.CONGRESS).toBe("congress-congress-united_states");
        expect(RE_EXPORTED_ENUM).toBe(ESwayLocaleName);
    });

    it("pins the VOTING_WEBSITES_BY_SWAY_LOCALE mapping", () => {
        expect(VOTING_WEBSITES_BY_SWAY_LOCALE[ESwayLocaleName.BALTIMORE]).toBe("Baltimore Legistar");
        expect(VOTING_WEBSITES_BY_SWAY_LOCALE[ESwayLocaleName.BALTIMORE_COUNTY]).toBe("Baltimore County Website");
        expect(VOTING_WEBSITES_BY_SWAY_LOCALE[ESwayLocaleName.LOS_ANGELES]).toBe("LACityClerk Connect");
        expect(VOTING_WEBSITES_BY_SWAY_LOCALE[ESwayLocaleName.WASHINGTON_DC]).toBe("Washington DC LIMS");
        expect(VOTING_WEBSITES_BY_SWAY_LOCALE[ESwayLocaleName.MARYLAND]).toBe("mgaleg.maryland.gov");
        expect(VOTING_WEBSITES_BY_SWAY_LOCALE[ESwayLocaleName.CONGRESS]).toBe("congress.gov");
        expect(RE_EXPORTED_WEBSITES).toBe(VOTING_WEBSITES_BY_SWAY_LOCALE);
    });
});
