import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

// @lat: [[verification-gates#Frontend onboarding coverage gate]]

const FLOOR_FILE = resolve(process.cwd(), "config/onboarding_coverage_floor.frontend.json");

const ONBOARDING_FILES = [
    "app/frontend/components/auth/PasskeyPanel.tsx",
    "app/frontend/components/user/NominatimAddressAutocomplete.tsx",
    "app/frontend/hooks/authentication/phone/useConfirmPhoneVerification.ts",
    "app/frontend/hooks/authentication/useWebAuthnRegistration.ts",
    "app/frontend/hooks/useNominatimAddressAutocomplete.ts",
    "app/frontend/pages/SwayRegistration.tsx",
    "app/frontend/sway_utils/parseNominatimAddress.ts",
    "app/frontend/sway_utils/rate_limit.ts",
    "app/frontend/sway_utils/webauthn.ts",
];

type Floors = Record<string, { line: number; branch: number }>;

const readFloors = (): Floors => JSON.parse(readFileSync(FLOOR_FILE, "utf8"));

describe("frontend onboarding coverage floors", () => {
    it("lists exactly the onboarding files", () => {
        expect(Object.keys(readFloors()).sort()).toEqual(ONBOARDING_FILES);
    });

    it("lists only files that exist", () => {
        const missing = Object.keys(readFloors()).filter((file) => !existsSync(resolve(process.cwd(), file)));
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
