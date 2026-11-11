/**
 // @lat: [[mobile-navigation-test-guards#Why AuthStack, AppDrawer labels, and header-title-audit read source as plain text]]
 */

import * as fs from "fs";
import * as path from "path";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

const ORGS_STACK_SRC = fs.readFileSync(path.join(__dirname, "..", "..", "src", "navigation", "OrgsStack.tsx"), "utf8");

describe("Phase 38 PARITY-18 — header back-title + PARITY_COPY title alignment", () => {
    it("OrgsStack pushed screen uses 'Organizations' backTitle (not 'Orgs')", () => {
        expect(ORGS_STACK_SRC).toMatch(/pushedScreenOptions\(colorScheme,\s*"Organizations"\)/);
        expect(ORGS_STACK_SRC).not.toMatch(/pushedScreenOptions\(colorScheme,\s*"Orgs"\)/);
    });

    it("PARITY_COPY canonical titles for in-scope screens are locked", () => {
        expect(PARITY_COPY.bills.title).toBe("Past bills");
        expect(PARITY_COPY.legislators.title).toBe("Legislators");
        expect(PARITY_COPY.orgs.title).toBe("Organizations");
        expect(PARITY_COPY.profile.title).toBe("Profile");
    });
});
