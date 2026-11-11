import { describe, expect, it } from "vitest";

import { getDistrictLegislatorNames } from "app/frontend/sway_utils";

describe("getDistrictLegislatorNames", () => {
    const district = { name: "D-1", number: 1, region_code: "D" } as any;

    it("returns only active legislators for the matching district when available", () => {
        const names = getDistrictLegislatorNames(district, [
            { full_name: "Inactive Rep", active: false, district } as any,
            { full_name: "Active Rep", active: true, district } as any,
            { full_name: "Other Rep", active: true, district: { ...district, name: "D-2", number: 2 } } as any,
        ]);

        expect(names).toEqual(["Active Rep"]);
    });

    it("returns all matching legislators when no active representative is found", () => {
        const names = getDistrictLegislatorNames(district, [
            { full_name: "Alex Jones", active: false, district } as any,
            { full_name: "Bri Smith", active: false, district } as any,
        ]);

        expect(names).toEqual(["Alex Jones", "Bri Smith"]);
    });
});
