/**
 // @lat: [[mobile-navigation-test-guards#Why AuthStack, AppDrawer labels, and header-title-audit read source as plain text#AuthStack.routes.spec.ts: guard rail for the sign-in navigation stack]]
 */

import * as fs from "fs";
import * as path from "path";

const AUTH_STACK_SRC = fs.readFileSync(path.join(__dirname, "..", "src", "navigation", "AuthStack.tsx"), "utf8");

const TYPES_SRC = fs.readFileSync(path.join(__dirname, "..", "src", "navigation", "types.ts"), "utf8");

describe("AuthStack two-route regression guard", () => {
    it("AuthStackParamList declares exactly Auth and DeviceUnsupported routes", () => {
        expect(TYPES_SRC).toContain("Auth: undefined;");
        expect(TYPES_SRC).toContain("DeviceUnsupported: undefined;");

        expect(TYPES_SRC).not.toMatch(/SignIn\s*:/);
        expect(TYPES_SRC).not.toMatch(/PhoneEntry\s*:/);
        expect(TYPES_SRC).not.toMatch(/PasskeyAuth\s*:/);
        expect(TYPES_SRC).not.toMatch(/SmsFallback\s*:/);
        expect(TYPES_SRC).not.toMatch(/SwayRegistration\s*:/);
    });

    it("AuthStack source file does not reference deleted screen module imports", () => {
        expect(AUTH_STACK_SRC).not.toContain("SignInScreen");
        expect(AUTH_STACK_SRC).not.toContain("PhoneEntryScreen");
        expect(AUTH_STACK_SRC).not.toContain("PasskeyAuthScreen");
        expect(AUTH_STACK_SRC).not.toContain("SmsFallbackScreen");
        expect(AUTH_STACK_SRC).not.toContain("SwayRegistrationScreen");
    });

    it("AuthStack source file declares exactly two Stack.Screen elements", () => {
        const matches = AUTH_STACK_SRC.match(/Stack\.Screen\s+name=/g);
        const count = matches ? matches.length : 0;
        expect(count).toBe(2);
    });

    it('AuthStack source file declares name="Auth" and name="DeviceUnsupported" routes', () => {
        expect(AUTH_STACK_SRC).toContain('name="Auth"');
        expect(AUTH_STACK_SRC).toContain('name="DeviceUnsupported"');
    });
});
