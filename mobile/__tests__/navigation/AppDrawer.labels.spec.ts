/**
 // @lat: [[mobile-navigation-test-guards#Why AuthStack, AppDrawer labels, and header-title-audit read source as plain text]]
 */

import * as fs from "fs";
import * as path from "path";

const APP_DRAWER_SRC = fs.readFileSync(path.join(__dirname, "..", "..", "src", "navigation", "AppDrawer.tsx"), "utf8");

describe("AppDrawer label parity guard", () => {
    it("declares drawerLabel for every drawer item", () => {
        expect(APP_DRAWER_SRC).toMatch(/drawerLabel:\s*PARITY_COPY\.feed\.title/);
        expect(APP_DRAWER_SRC).toMatch(/drawerLabel:\s*PARITY_COPY\.billOfTheMonth\.title/);
        expect(APP_DRAWER_SRC).toMatch(/drawerLabel:\s*"Bills"/);
        expect(APP_DRAWER_SRC).toMatch(/drawerLabel:\s*"Legislators"/);
        expect(APP_DRAWER_SRC).toMatch(/drawerLabel:\s*"Organizations"/);
        expect(APP_DRAWER_SRC).toMatch(/drawerLabel:\s*"Profile"/);
        expect(APP_DRAWER_SRC).toMatch(/drawerLabel:\s*"Admin"/);
    });

    it("never labels the Bill of the Month item as Home", () => {
        expect(APP_DRAWER_SRC).not.toMatch(/drawerLabel:\s*"Home"/);
    });

    it("never reverts the Orgs drawer label to the abbreviated form", () => {
        expect(APP_DRAWER_SRC).not.toMatch(/drawerLabel:\s*"Orgs"/);
    });
});
