import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

// @lat: [[verification-gates#Mobile onboarding coverage gate]]

const FLOOR_FILE = resolve(__dirname, "../../config/onboarding_coverage_floor.mobile.json");
const REPO_ROOT = resolve(__dirname, "../..");

const ONBOARDING_FILES = [
    "mobile/src/api/client.ts",
    "mobile/src/auth/passkeyAuth.ts",
    "mobile/src/auth/smsAuth.ts",
    "mobile/src/components/AddressAutocomplete.tsx",
    "mobile/src/screens/AddressScreen.tsx",
    "mobile/src/screens/AuthScreen.tsx",
    "mobile/src/state/BootstrapContext.tsx",
];

type Floors = Record<string, { line: number; branch: number }>;

const readFloors = (): Floors => JSON.parse(readFileSync(FLOOR_FILE, "utf8"));

describe("mobile onboarding coverage floors", () => {
    it("lists exactly the onboarding files", () => {
        expect(Object.keys(readFloors()).sort()).toEqual(ONBOARDING_FILES);
    });

    it("lists only files that exist", () => {
        const missing = Object.keys(readFloors()).filter((file) => !existsSync(resolve(REPO_ROOT, file)));
        expect(missing).toEqual([]);
    });

    it("gives every file a line and a branch floor between 0 and 100", () => {
        Object.values(readFloors()).forEach((floor) => {
            [floor.line, floor.branch].forEach((percent) => {
                expect(typeof percent).toBe("number");
                expect(percent).toBeGreaterThanOrEqual(0);
                expect(percent).toBeLessThanOrEqual(100);
            });
        });
    });
});
