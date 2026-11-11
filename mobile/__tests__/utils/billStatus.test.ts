// @lat: [[mobile-bill-surface-components-design#BillHeader]]
import { billStatusColor, billStatusLabel } from "../../src/utils/billStatus";
import { swayTokens } from "../../src/theme/tokens";

describe("billStatusColor", () => {
    test("returns null when the bill has no status", () => {
        expect(billStatusColor(undefined)).toBeNull();
        expect(billStatusColor(null)).toBeNull();
        expect(billStatusColor("")).toBeNull();
    });

    test.each([
        ["passed", "success"],
        ["failed", "destructive"],
        ["vetoed", "destructive"],
        ["committee", "warning"],
        ["introduced", "mutedForeground"],
    ] as const)("maps %s onto the %s token of the requested scheme", (status, token) => {
        expect(billStatusColor(status, "light")).toBe(swayTokens.light[token]);
        expect(billStatusColor(status, "dark")).toBe(swayTokens.dark[token]);
    });

    test("matches the status case-insensitively", () => {
        expect(billStatusColor("Passed", "dark")).toBe(swayTokens.dark.success);
    });

    test("defaults to the light palette when no scheme is given", () => {
        expect(billStatusColor("passed")).toBe(swayTokens.light.success);
    });
});

describe("billStatusLabel", () => {
    test("capitalises the first letter of the status", () => {
        expect(billStatusLabel("passed")).toBe("Passed");
    });
});
