import { describe, expect, it } from "vitest";
import { placeholderFillPercentages } from "app/frontend/styles/themes/__tests__/placeholderFill";
import { THEME_NAMES, themeCss } from "app/frontend/styles/themes/__tests__/themeFiles";
import { declarationsIn, namesAnUnreadableColour, notationOf, toHex } from "./colourNotation";

// @lat: [[theme-test-suite-silent-failure-guards#Contrast floor: KNOWN_SHORTFALLS is a debt list, not a setting]]

const toLinear = (channel: number): number => {
    const c = channel / 255;
    return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
};

const relativeLuminance = (hex: string): number => {
    const h = hex.replace("#", "");
    const [r, g, b] = [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16));
    return 0.2126 * toLinear(r) + 0.7152 * toLinear(g) + 0.0722 * toLinear(b);
};

const contrastRatio = (a: string, b: string): number => {
    const [lighter, darker] = [relativeLuminance(a), relativeLuminance(b)].sort((x, y) => y - x);
    return (lighter + 0.05) / (darker + 0.05);
};

// Tailwind's `/12` suffix makes a colour 12% opaque, so it blends with whatever
// sits behind it. That blend is what the text really sits on, so tinted fills
// have to be measured against the blend, not against the raw colour.
const channels = (hex: string): number[] => {
    const h = hex.replace("#", "");
    return [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16));
};

const composite = (fg: string, alpha: number, bg: string): string => {
    const [f, b] = [channels(fg), channels(bg)];
    const mixed = f.map((channel, i) => Math.round(channel * alpha + b[i] * (1 - alpha)));
    return `#${mixed.map((v) => v.toString(16).padStart(2, "0")).join("")}`;
};

// @lat: [[theme-test-suite-silent-failure-guards#Colour notation: one shared module for two gates that used to disagree]]

interface ModeBlock {
    /** Fully opaque colour variables, converted to #rrggbb. */
    tokens: Record<string, string>;
    /** Declarations that name a colour this file cannot measure. */
    unsupported: string[];
    /** False when the selector does not appear in this file at all. */
    present: boolean;
}

// The match must start at the beginning of a line, so a selector merely
// mentioned inside a comment is never mistaken for the real rule.
const blockBody = (css: string, selector: string): string | null => {
    const opener = new RegExp(`^[ \\t]*${selector.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\s*\\{`, "m").exec(css);
    if (!opener) return null;
    const open = opener.index + opener[0].length - 1;
    return css.slice(open + 1, css.indexOf("}", open));
};

const modeTokens = (css: string, selector: string): ModeBlock => {
    const body = blockBody(css, selector);
    if (body === null) return { tokens: {}, unsupported: [], present: false };

    const tokens: Record<string, string> = {};
    const unsupported: string[] = [];
    for (const { name, value } of declarationsIn(body)) {
        const hex = toHex(value);
        if (hex) {
            tokens[name] = hex;
            continue;
        }
        if (namesAnUnreadableColour(value)) unsupported.push(`${name}: ${value} (${notationOf(value)})`);
    }
    return { tokens, unsupported, present: true };
};

interface Pair {
    fg: string;
    bg: string;
    /** The surface is `token` blended over `bg` at `alpha` opacity — Tailwind's `bg-x/12`. */
    tint?: { token: string; alpha: number };
    /** 4.5 for body text, 3.0 for large text and non-text indicators (WCAG 2.1). */
    min: number;
    what: string;
}

// @lat: [[theme-test-suite-silent-failure-guards#Contrast floor: KNOWN_SHORTFALLS is a debt list, not a setting]]
const STAMP_TONES = ["success", "warning", "info", "destructive", "primary"] as const;

const stampPairs: Pair[] = STAMP_TONES.map((tone) => ({
    fg: `--${tone}`,
    bg: "--card",
    tint: { token: `--${tone}`, alpha: 0.12 },
    min: 4.5,
    what: `the ${tone} stamp badge`,
}));

// @lat: [[theme-test-suite-silent-failure-guards#Contrast floor: KNOWN_SHORTFALLS is a debt list, not a setting]]
const SURFACES = ["--surface-1", "--surface-2", "--surface-3"] as const;

const surfacePairs: Pair[] = SURFACES.map((surface) => ({
    fg: "--muted-foreground",
    bg: surface,
    min: 4.5,
    what: `muted text on ${surface.replace("--", "")}`,
}));

// @lat: [[theme-tokens#Why the non-text tokens are measured too]]
// --muted-icon: the accordion/select/combobox chevrons.
// --chart-muted: the neutral bar in VoterAgreementChart, drawn on a --muted track.
// --border-strong: the edge of input.tsx and button.tsx, whose fills sit within
// 1.15:1 of the page in every theme.
const nonTextPairs: Pair[] = [
    { fg: "--muted-icon", bg: "--background", min: 3.0, what: "a muted icon on the page" },
    { fg: "--muted-icon", bg: "--card", min: 3.0, what: "a muted icon on a card" },
    { fg: "--muted-icon", bg: "--surface-2", min: 3.0, what: "a muted icon on surface-2" },
    { fg: "--chart-muted", bg: "--muted", min: 3.0, what: "the neutral chart bar on its track" },
    { fg: "--border-strong", bg: "--background", min: 3.0, what: "a control edge against the page" },
];

const PAIRS: Pair[] = [
    { fg: "--foreground", bg: "--background", min: 4.5, what: "body text on the page" },
    { fg: "--card-foreground", bg: "--card", min: 4.5, what: "text on a card" },
    { fg: "--popover-foreground", bg: "--popover", min: 4.5, what: "text in a popover" },
    { fg: "--muted-foreground", bg: "--background", min: 4.5, what: "muted text on the page" },
    { fg: "--primary-foreground", bg: "--primary", min: 4.5, what: "text on a primary fill" },
    { fg: "--accent-foreground", bg: "--accent", min: 4.5, what: "text on an accent fill" },
    { fg: "--success-foreground", bg: "--success", min: 4.5, what: "text on a success fill" },
    { fg: "--warning-foreground", bg: "--warning", min: 4.5, what: "text on a warning fill" },
    { fg: "--info-foreground", bg: "--info", min: 4.5, what: "text on an info fill" },
    { fg: "--background", bg: "--destructive", min: 4.5, what: "text on a destructive fill" },
    { fg: "--success", bg: "--background", min: 4.5, what: "text-success on the page" },
    { fg: "--destructive", bg: "--background", min: 4.5, what: "destructive text on the page" },
    { fg: "--ring", bg: "--background", min: 3.0, what: "the focus ring against the page" },
    { fg: "--vote-for", bg: "--background", min: 3.0, what: "the FOR indicator on the page" },
    { fg: "--vote-against", bg: "--background", min: 3.0, what: "the AGAINST indicator on the page" },
    // VotePanel renders the cast FOR button as `bg-vote-for text-success-foreground`.
    { fg: "--success-foreground", bg: "--vote-for", min: 4.5, what: "the cast FOR label on its fill" },
    ...stampPairs,
    ...surfacePairs,
    ...nonTextPairs,
];

// Keys look like `${theme}/${mode} ${fg} on ${bg}`. The list is empty, and the
// intent is that it stays empty.
//
// @lat: [[theme-test-suite-silent-failure-guards#Contrast floor: KNOWN_SHORTFALLS is a debt list, not a setting]]
const KNOWN_SHORTFALLS = new Set<string>([]);

interface Measurement {
    key: string;
    ratio: number;
    min: number;
    detail: string;
}

// Every place a theme file declares a full set of colours.
// @lat: [[theme-test-suite-silent-failure-guards#Contrast floor: KNOWN_SHORTFALLS is a debt list, not a setting#Why the auto mode and (data-intensity) blocks are handled the way they are]]
const MODES = ["light", "dark", "auto"] as const;
type Mode = (typeof MODES)[number];

const selectorFor = (theme: string, mode: Mode): string => {
    if (mode === "dark") return `[data-theme="${theme}"].dark`;
    if (mode === "auto") return `[data-theme="${theme}"][data-theme-mode="auto"]`;
    return `[data-theme="${theme}"]`;
};

// One place turns (theme, mode) into every measured pair, so the contrast check
// and the stale-entry check can never disagree about what a key means.
const measure = (theme: string, mode: Mode): Measurement[] => {
    const { tokens } = modeTokens(themeCss(theme), selectorFor(theme, mode));

    const measurements: Measurement[] = [];
    for (const { fg, bg, tint, min, what } of PAIRS) {
        const fgHex = tokens[fg];
        const bgBase = tokens[bg];
        // Variables written as rgba() (such as --scrim) are out of scope.
        if (!fgHex || !bgBase) continue;
        if (tint && !tokens[tint.token]) continue;

        const bgHex = tint ? composite(tokens[tint.token], tint.alpha, bgBase) : bgBase;
        const key = tint
            ? `${theme}/${mode} ${fg} on ${tint.token}/${tint.alpha * 100} over ${bg}`
            : `${theme}/${mode} ${fg} on ${bg}`;
        const ratio = contrastRatio(fgHex, bgHex);

        measurements.push({ key, ratio, min, detail: `${what}: ${fgHex} on ${bgHex}` });
    }
    return measurements;
};

describe("theme contrast floor", () => {
    const themes = THEME_NAMES;

    for (const theme of themes) {
        for (const mode of MODES) {
            it(`${theme} (${mode}) meets the contrast floor on every checked pair`, () => {
                const measurements = measure(theme, mode);
                expect(measurements.length).toBeGreaterThan(0);

                const failures = measurements
                    .filter((m) => m.ratio < m.min && !KNOWN_SHORTFALLS.has(m.key))
                    .map((m) => `${m.detail} is ${m.ratio.toFixed(2)}:1, needs ${m.min}:1  [${m.key}]`);

                expect(failures).toEqual([]);
            });
        }
    }

    // Reading the file is what turns "these blocks hold no colours" into a
    // checked claim, instead of the excuse for never measuring them.
    describe("the blocks this file deliberately does not measure", () => {
        const INTENSITIES = ["bold", "calm"] as const;

        for (const theme of themes) {
            it(`${theme}'s intensity blocks move no colour token`, () => {
                const css = themeCss(theme);
                const blocks = [
                    ...INTENSITIES.map((i) => `[data-theme="${theme}"][data-intensity="${i}"]`),
                    ...INTENSITIES.map((i) => `[data-theme="${theme}"].dark[data-intensity="${i}"]`),
                    ...INTENSITIES.map((i) => `[data-theme="${theme}"][data-theme-mode="auto"][data-intensity="${i}"]`),
                ];

                for (const selector of blocks) {
                    const block = modeTokens(css, selector);
                    expect(block.present, `${selector} is missing`).toBe(true);
                    expect(Object.keys(block.tokens), `${selector} declares a colour token`).toEqual([]);
                    expect(block.unsupported, `${selector} declares a colour token`).toEqual([]);
                }
            });
        }
    });

    // @lat: [[theme-test-suite-silent-failure-guards#Contrast floor: KNOWN_SHORTFALLS is a debt list, not a setting]]
    for (const theme of themes) {
        it(`${theme}'s auto (prefers-color-scheme) palette matches its explicit dark palette`, () => {
            const css = themeCss(theme);
            const dark = modeTokens(css, selectorFor(theme, "dark"));
            const auto = modeTokens(css, selectorFor(theme, "auto"));

            expect(dark.present).toBe(true);
            expect(auto.present).toBe(true);
            expect(Object.keys(dark.tokens).length).toBeGreaterThan(0);
            expect(auto.tokens).toEqual(dark.tokens);
        });
    }

    // @lat: [[theme-test-suite-silent-failure-guards#Contrast floor: KNOWN_SHORTFALLS is a debt list, not a setting]]
    it("measures every colour token it can see, and names any notation it cannot", () => {
        const unsupported: string[] = [];
        for (const theme of themes) {
            const css = themeCss(theme);
            for (const mode of MODES) {
                for (const declaration of modeTokens(css, selectorFor(theme, mode)).unsupported) {
                    unsupported.push(`${theme}/${mode} ${declaration}`);
                }
            }
        }

        expect(unsupported).toEqual([]);
    });

    // Keeps the debt list honest: an entry that no longer fails has to be
    // deleted, so the list can only shrink.
    it("records no shortfall that has since been fixed", () => {
        const measured = new Map<string, Measurement>();
        for (const theme of themes) {
            for (const mode of MODES) {
                for (const m of measure(theme, mode)) measured.set(m.key, m);
            }
        }

        const stale: string[] = [];
        for (const key of KNOWN_SHORTFALLS) {
            const m = measured.get(key);
            if (!m) {
                stale.push(`${key} no longer matches any measured pair — remove it from KNOWN_SHORTFALLS`);
            } else if (m.ratio >= m.min) {
                stale.push(`${key} now passes — remove it from KNOWN_SHORTFALLS`);
            }
        }

        expect(stale).toEqual([]);
    });
});

// @lat: [[navigation-placeholder-tracer#Why the pulse keyframes moved from 12%/20% to 16%/24%, and resting stayed at 16%]]
const PLACEHOLDER_FILL_PERCENTAGES = placeholderFillPercentages();

// 69-UI-SPEC.md Pulse section, not a WCAG ratio.
// @lat: [[navigation-placeholder-tracer#Where the placeholder fill's 1.2:1 floor comes from]]
const PLACEHOLDER_FILL_FLOOR = 1.2;

describe("placeholder fill contrast floor", () => {
    const themes = THEME_NAMES;

    // A positive control on the derivation itself: a regex that matched nothing would
    // otherwise leave the loop below with no mix to measure and every theme green.
    it("derives every fill percentage from application.css, not from a copy of it", () => {
        const entries = Object.entries(PLACEHOLDER_FILL_PERCENTAGES);

        expect(entries.length).toBeGreaterThanOrEqual(2);
        for (const [label, pct] of entries) {
            expect(Number.isInteger(pct), `${label} is not a whole percentage`).toBe(true);
            expect(pct, `${label} is outside 1-99%`).toBeGreaterThan(0);
            expect(pct, `${label} is outside 1-99%`).toBeLessThan(100);
        }
    });

    for (const theme of themes) {
        for (const mode of MODES) {
            it(`${theme} (${mode}) placeholder fill clears ${PLACEHOLDER_FILL_FLOOR}:1 at rest and both pulse ends`, () => {
                const { tokens, present } = modeTokens(themeCss(theme), selectorFor(theme, mode));
                expect(present, `${theme}/${mode} block is missing entirely`).toBe(true);

                const bg = tokens["--background"];
                const fg = tokens["--muted-foreground"];
                expect(bg, `${theme}/${mode} is missing --background`).toBeDefined();
                expect(fg, `${theme}/${mode} is missing --muted-foreground`).toBeDefined();

                for (const [label, pct] of Object.entries(PLACEHOLDER_FILL_PERCENTAGES)) {
                    const mixed = composite(fg, pct / 100, bg);
                    const ratio = contrastRatio(mixed, bg);
                    expect(
                        ratio,
                        `${theme}/${mode} placeholder fill at ${label} (${pct}%) is ${ratio.toFixed(2)}:1, needs ${PLACEHOLDER_FILL_FLOOR}:1`,
                    ).toBeGreaterThanOrEqual(PLACEHOLDER_FILL_FLOOR);
                }
            });
        }
    }
});
