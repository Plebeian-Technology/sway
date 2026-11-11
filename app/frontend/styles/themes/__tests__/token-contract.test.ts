import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, it, expect } from "vitest";
import { THEME_FILES, THEMES_DIR } from "app/frontend/styles/themes/__tests__/themeFiles";

// @lat: [[theme-tokens#Why a test enforces the vocabulary]]

// --- TIER 1: MODE_VARIANT (color) — base + .dark + @media auto --------------
const COLOR_TOKENS = [
    "--background",
    "--foreground",
    "--card",
    "--card-foreground",
    "--popover",
    "--popover-foreground",
    "--primary",
    "--primary-foreground",
    "--secondary",
    "--secondary-foreground",
    "--muted",
    "--muted-foreground",
    "--accent",
    "--accent-foreground",
    "--destructive",
    "--border",
    "--border-soft",
    "--border-strong",
    "--input",
    "--ring",
    "--success",
    "--success-foreground",
    "--warning",
    "--warning-foreground",
    "--info",
    "--info-foreground",
    "--surface-1",
    "--surface-2",
    "--surface-3",
    "--vote-for",
    "--vote-against",
    "--muted-icon",
    "--avatar-border",
    "--chart-muted",
    "--scrim",
] as const;

// --- TIER 2: MODE_INVARIANT — base block only -------------------------------

const TYPE_TOKENS = [
    "--font-display",
    "--font-body",
    "--font-numeric",
    "--type-display",
    "--type-h2",
    "--type-h3",
    "--type-lede",
    "--type-body",
    "--type-small",
    "--type-micro",
    "--type-stat",
    "--weight-body",
    "--weight-medium",
    "--weight-bold",
    "--weight-display",
    "--leading-display",
    "--leading-heading",
    "--leading-body",
    "--tracking-display",
    "--tracking-body",
    "--tracking-caps",
] as const;

// @lat: [[theme-tokens#Why density and motion belong to the theme]]
const DENSITY_TOKENS = [
    "--space-unit",
    "--measure",
    "--content-max",
    "--control-pad-x",
    "--chart-label-gutter",
] as const;

const SHAPE_TOKENS = ["--radius", "--radius-sm", "--radius-md"] as const;

// RULE — how thick divider lines are (separate from the border COLOR variables
// above) plus their style (solid / double / dashed).
const RULE_TOKENS = ["--rule-hair", "--rule-mid", "--rule-thick", "--rule-style"] as const;

// TEXTURE — a `background-image` value for the page itself; `none` for themes
// that carry no grain.
const TEXTURE_TOKENS = ["--texture-page"] as const;

// MOTION — how long interactions take and the easing curve for small movements.
const MOTION_TOKENS = ["--dur-1", "--dur-2", "--dur-3", "--ease-out"] as const;

const MODE_INVARIANT_TOKENS = [
    ...TYPE_TOKENS,
    ...DENSITY_TOKENS,
    ...SHAPE_TOKENS,
    ...RULE_TOKENS,
    ...TEXTURE_TOKENS,
    ...MOTION_TOKENS,
] as const;

// --- TIER 3: INTENSITY — base block + every [data-intensity] block ----------
const INTENSITY_TOKENS = ["--neo-border-width", "--neo-shadow"] as const;

// Which variables each block should declare, keyed by the selector with the
// `[data-theme="…"]` prefix removed so it reads the same for every theme. The
// base block carries every tier; .dark / @media auto carry color only;
// [data-intensity] blocks carry the intensity variables only.
const colorSet = new Set<string>(COLOR_TOKENS);
const intensitySet = new Set<string>(INTENSITY_TOKENS);
const baseSet = new Set<string>([...COLOR_TOKENS, ...MODE_INVARIANT_TOKENS, ...INTENSITY_TOKENS]);

const EXPECTED_BY_MODE = new Map<string, Set<string>>([
    [":root", baseSet],
    [".dark", colorSet],
    ['[data-theme-mode="auto"]', colorSet],
    ['[data-intensity="bold"]', intensitySet],
    ['[data-intensity="calm"]', intensitySet],
    ['.dark[data-intensity="bold"]', intensitySet],
    ['.dark[data-intensity="calm"]', intensitySet],
    ['[data-theme-mode="auto"][data-intensity="bold"]', intensitySet],
    ['[data-theme-mode="auto"][data-intensity="calm"]', intensitySet],
]);

// --- CSS parsing, done by hand because no new dependencies are allowed -------

interface CssBlock {
    selector: string;
    body: string;
}

// Collect the NAMES (not the values) of the CSS variables declared in a block.
function tokenNames(css: string): Set<string> {
    const re = /^\s*(--[a-z0-9-]+)\s*:/gm;
    const set = new Set<string>();
    for (const match of css.matchAll(re)) {
        set.add(match[1]);
    }
    return set;
}

// Remove /* ... */ comments, so a comment sitting just before a selector does
// not get glued onto that block's header (which would give matching blocks in
// different theme files different keys).
function stripComments(css: string): string {
    return css.replace(/\/\*[\s\S]*?\*\//g, "");
}

// Walk the CSS and return every rule block that declares variables directly.
// @media blocks are stepped into so the rules inside them are collected one by
// one (the @media wrapper itself declares no variables).
function ruleBlocks(css: string): CssBlock[] {
    const blocks: CssBlock[] = [];
    let i = 0;
    while (i < css.length) {
        const open = css.indexOf("{", i);
        if (open === -1) break;

        const header = css.slice(i, open).trim();

        // Find the matching close brace for this block.
        let depth = 1;
        let j = open + 1;
        while (j < css.length && depth > 0) {
            if (css[j] === "{") depth += 1;
            else if (css[j] === "}") depth -= 1;
            j += 1;
        }
        const body = css.slice(open + 1, j - 1);

        if (header.startsWith("@media")) {
            // Step inside the at-rule; the blocks within it hold the variables.
            blocks.push(...ruleBlocks(body));
        } else {
            blocks.push({ selector: header, body });
        }
        i = j;
    }
    return blocks;
}

// Turn a selector into a key that reads the same for every theme, by removing
// the `[data-theme="<name>"]` prefix so matching blocks in different files line
// up. Runs of whitespace collapse to one space so an @media header split across
// several lines still matches.
function modeKey(selector: string): string {
    const key = selector
        .replace(/\[data-theme="[a-z0-9-]+"\]/g, "")
        .replace(/\s+/g, " ")
        .trim();
    return key === "" ? ":root" : key;
}

// Map every block key to the set of variable names declared in that block.
function tokensByMode(css: string): Map<string, Set<string>> {
    const byMode = new Map<string, Set<string>>();
    for (const block of ruleBlocks(stripComments(css))) {
        const key = modeKey(block.selector);
        const existing = byMode.get(key) ?? new Set<string>();
        for (const name of tokenNames(block.body)) {
            existing.add(name);
        }
        byMode.set(key, existing);
    }
    return byMode;
}

describe("token contract — every theme declares the canonical token set", () => {
    it("themes/ contains the known theme files", () => {
        expect(THEME_FILES).toEqual(expect.arrayContaining(["cornerstore.css", "sway.css"]));
    });

    for (const file of THEME_FILES) {
        describe(`${file}`, () => {
            const byMode = tokensByMode(readFileSync(resolve(THEMES_DIR, file), "utf8"));

            it("declares exactly the contract's mode blocks", () => {
                expect([...byMode.keys()].sort()).toEqual([...EXPECTED_BY_MODE.keys()].sort());
            });

            for (const [mode, expected] of EXPECTED_BY_MODE) {
                it(`mode "${mode}" declares exactly its contract tokens`, () => {
                    const actual = byMode.get(mode) ?? new Set<string>();
                    const missing = [...expected].filter((t) => !actual.has(t)).sort();
                    const extra = [...actual].filter((t) => !expected.has(t)).sort();

                    expect(missing).toEqual([]);
                    expect(extra).toEqual([]);
                });
            }
        });
    }
});

// --- The 44px touch-target floor --------------------------------------------

// @lat: [[theme-tokens#Why density and motion belong to the theme]]
describe("control-height floor — the token stays at or above 44px", () => {
    it("tokens.css declares --control-height at >= 2.75rem (44px)", () => {
        const css = readFileSync(resolve(THEMES_DIR, "..", "tokens.css"), "utf8");
        const match = /--control-height:\s*(-?\d*\.?\d+)rem/.exec(css);
        if (!match) throw new Error("--control-height is not declared in tokens.css");

        const px = Number(match[1]) * 16;
        expect(px).toBeGreaterThanOrEqual(44);
    });
});
