// @lat: [[theme-test-suite-silent-failure-guards#Theme-id allowlist: two hand-maintained lists with nothing generating one from the other#The THEMES manifest itself (app/frontend/styles/themes/index.ts)]]

export type ThemeId = "sway" | "banner" | "ballot" | "cornerstore" | "monochrome" | "service-manual" | "swiss-grid";

export interface Theme {
    readonly id: ThemeId;
    readonly label: string;
    readonly fontStack: string;
    readonly defaultIntensity: "bold" | "calm";
    readonly hidden?: boolean;
}

export const THEMES: readonly Theme[] = [
    {
        id: "sway",
        label: "Sway",
        fontStack:
            '"OpenSans", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Oxygen, Ubuntu, Cantarell, "Helvetica Neue", sans-serif',
        defaultIntensity: "bold",
    },
    {
        id: "banner",
        label: "Banner",
        fontStack: '"Mona Sans", "Hanken Grotesk", -apple-system, "Helvetica Neue", Arial, sans-serif',
        defaultIntensity: "bold",
        hidden: true,
    },
    {
        id: "ballot",
        label: "Ballot",
        fontStack: '"Barlow Semi Condensed", "Barlow", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
        defaultIntensity: "bold",
    },
    {
        id: "cornerstore",
        label: "Corner Store",
        fontStack: '"Libre Franklin", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
        defaultIntensity: "bold",
    },
    {
        id: "monochrome",
        label: "Monochrome",
        fontStack: '"Inter", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
        defaultIntensity: "bold",
    },
    {
        id: "service-manual",
        label: "Service Manual",
        fontStack: '"Inter", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
        defaultIntensity: "bold",
    },
    {
        id: "swiss-grid",
        label: "Swiss Notice",
        fontStack: '"Inter", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
        defaultIntensity: "bold",
    },
] as const;

// @lat: [[theme-test-suite-silent-failure-guards#Theme-id allowlist: two hand-maintained lists with nothing generating one from the other#The THEMES manifest itself (app/frontend/styles/themes/index.ts)]]
export function isValidThemeId(value: unknown): value is ThemeId {
    return THEMES.some((t) => t.id === value);
}
