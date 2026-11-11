import { shadowBold, shadowCalm } from "../../src/theme/effects";
import { swayTokens } from "../../src/theme/tokens";

const EXPECTED_TOKEN_KEYS = [
    "background",
    "foreground",
    "card",
    "cardForeground",
    "popover",
    "popoverForeground",
    "primary",
    "primaryForeground",
    "secondary",
    "secondaryForeground",
    "muted",
    "mutedForeground",
    "accent",
    "accentForeground",
    "destructive",
    "border",
    "borderSoft",
    "borderStrong",
    "input",
    "ring",
    "success",
    "successForeground",
    "warning",
    "warningForeground",
    "info",
    "infoForeground",
    "surface1",
    "surface2",
    "surface3",
    "voteFor",
    "voteAgainst",
    // Keys the token emitter now produces and the UI relies on at runtime.
    "mutedIcon", // avatar fallback icon colour
    "avatarBorder", // avatar ring border
    "chartMuted", // muted series in score bar charts
    "scrim", // modal/sheet backdrop overlay
    // @lat: [[theme-token-contract#Mobile's twin: swayTokens]]
] as const;

describe("swayTokens — token-name parity (PARITY-02)", () => {
    test("light variant exports all 35 v2 token keys", () => {
        for (const key of EXPECTED_TOKEN_KEYS) {
            expect(swayTokens.light).toHaveProperty(key);
        }
        expect(Object.keys(swayTokens.light).length).toBeGreaterThanOrEqual(EXPECTED_TOKEN_KEYS.length);
    });

    test("dark variant exports all 35 v2 token keys", () => {
        for (const key of EXPECTED_TOKEN_KEYS) {
            expect(swayTokens.dark).toHaveProperty(key);
        }
        expect(Object.keys(swayTokens.dark).length).toBeGreaterThanOrEqual(EXPECTED_TOKEN_KEYS.length);
    });

    test("light and dark variants have the same key set", () => {
        const lightKeys = Object.keys(swayTokens.light).sort();
        const darkKeys = Object.keys(swayTokens.dark).sort();
        expect(lightKeys).toEqual(darkKeys);
    });
});

describe("effects.shadowBold — sway soft Bootstrap shadow (Phase 58)", () => {
    test("light returns soft drop shadow (rgba black, low opacity)", () => {
        // @lat: [[theme-token-contract#Mobile's twin: swayTokens]]
        const s = shadowBold("light");
        expect(s.shadowColor).toBe("#000000");
        expect(s.shadowOffset).toEqual({ width: 0, height: 3 });
        expect(s.shadowOpacity).toBe(0.1);
        expect(s.shadowRadius).toBe(6);
        expect(s.elevation).toBe(3);
    });

    test("dark returns elevated drop shadow (rgba black, medium opacity)", () => {
        const s = shadowBold("dark");
        expect(s.shadowColor).toBe("#000000");
        expect(s.shadowOffset).toEqual({ width: 0, height: 2 });
        expect(s.shadowOpacity).toBe(0.5);
        expect(s.shadowRadius).toBe(4);
        expect(s.elevation).toBe(4);
    });
});

describe("effects.shadowCalm — flat-no-shadow variant (PARITY-02)", () => {
    test("returns transparent zero-offset shadow", () => {
        expect(shadowCalm.shadowColor).toBe("transparent");
        expect(shadowCalm.shadowOffset).toEqual({ width: 0, height: 0 });
        expect(shadowCalm.shadowOpacity).toBe(0);
        expect(shadowCalm.shadowRadius).toBe(0);
        expect(shadowCalm.elevation).toBe(0);
    });
});

describe("swayTokens — Sway theme values", () => {
    test("light variant matches sway.css token values", () => {
        // @lat: [[theme-tokens#Why the mobile app generates its palette from sway.css]]
        expect(swayTokens.light.background).toBe("#f7f9fc");
        expect(swayTokens.light.foreground).toBe("#363636");
        expect(swayTokens.light.primary).toBe("#3260db");
        expect(swayTokens.light.accent).toBe("#3260db");
        expect(swayTokens.light.border).toBe("#dee2e6");
        expect(swayTokens.light.voteFor).toBe("#1f7a45");
        expect(swayTokens.light.voteAgainst).toBe("#c62b38");
        expect(swayTokens.light.ring).toBe("#3260db");
        expect(swayTokens.light.scrim).toBe("rgba(0, 0, 0, 0.5)");
    });

    test("dark variant matches sway.css token values", () => {
        // @lat: [[theme-tokens#Why the mobile app generates its palette from sway.css]]
        expect(swayTokens.dark.background).toBe("#212529");
        expect(swayTokens.dark.foreground).toBe("#dee2e6");
        expect(swayTokens.dark.card).toBe("#2b3035");
        expect(swayTokens.dark.primary).toBe("#7db5f3");
        expect(swayTokens.dark.accent).toBe("#7db5f3");
        expect(swayTokens.dark.border).toBe("#495057");
        expect(swayTokens.dark.voteFor).toBe("#6dd7a0");
        expect(swayTokens.dark.voteAgainst).toBe("#f08d94");
        expect(swayTokens.dark.ring).toBe("#7db5f3");
        expect(swayTokens.dark.scrim).toBe("rgba(0, 0, 0, 0.7)");
    });
});
