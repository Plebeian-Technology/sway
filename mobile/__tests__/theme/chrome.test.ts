import { BAND_FOREGROUND, chromeColors } from "../../src/theme/chrome";
import { swayTokens } from "../../src/theme/tokens";
import { readableForeground } from "../../src/components/StampedBadge";
import { BRAND_HEADER_MIN_HEIGHT } from "../../src/components/BrandHeader";

describe("chromeColors", () => {
    test("the light band is the brand primary", () => {
        // @lat: [[mobile-chrome-and-scroll-layout#Brand band colours]]
        expect(chromeColors("light").band).toBe(swayTokens.light.primary);
    });

    test("the dark band is the deep blue surface with a primary edge", () => {
        // @lat: [[mobile-chrome-and-scroll-layout#Brand band colours]]
        const dark = chromeColors("dark");
        expect(dark.band).toBe(swayTokens.dark.surface3);
        expect(dark.bandEdge).toBe(swayTokens.dark.primary);
        expect(dark.bandEdgeWidth).toBeGreaterThan(0);
    });

    test.each(["light", "dark"] as const)("white text is the readable foreground on the %s band", (scheme) => {
        // @lat: [[mobile-chrome-and-scroll-layout#Brand band colours]]
        expect(readableForeground(chromeColors(scheme).band)).toBe(BAND_FOREGROUND);
    });
});

describe("pinned header budget", () => {
    test("the header and an offline banner take at most a quarter of a 667pt screen", () => {
        // @lat: [[mobile-chrome-and-scroll-layout#The pinned header is one 56pt row]]
        const OFFLINE_BANNER_ALLOWANCE = 44;
        const SMALL_PHONE_HEIGHT = 667;
        expect((BRAND_HEADER_MIN_HEIGHT + OFFLINE_BANNER_ALLOWANCE) / SMALL_PHONE_HEIGHT).toBeLessThanOrEqual(0.25);
    });
});
