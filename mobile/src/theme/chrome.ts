// @lat: [[mobile-chrome-and-scroll-layout#Brand band colours]]
import { swayTokens, type SwayColorScheme } from "./tokens";

export const BAND_FOREGROUND = "#ffffff";

export interface ChromeColors {
    band: string;
    bandForeground: string;
    bandForegroundMuted: string;
    bandEdge: string;
    bandEdgeWidth: number;
}

export const chromeColors = (colorScheme: SwayColorScheme): ChromeColors => {
    const t = swayTokens[colorScheme];
    const dark = colorScheme === "dark";
    return {
        band: dark ? t.surface3 : t.primary,
        bandForeground: BAND_FOREGROUND,
        bandForegroundMuted: "rgba(255, 255, 255, 0.82)",
        bandEdge: dark ? t.primary : "rgba(255, 255, 255, 0)",
        bandEdgeWidth: dark ? 2 : 0,
    };
};
