import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { THEME_FILES, THEMES_DIR } from "app/frontend/styles/themes/__tests__/themeFiles";

// @lat: [[theme-tokens#Why the type ladder has to stay monotonic]]

// Major Second (9:8).
const MIN_STEP_RATIO = 1.125;

// application.css maps each of these onto one Tailwind text-* utility, in this
// order: text-xs, text-sm, text-base, text-lg, text-xl, text-2xl, text-3xl,
// text-4xl.
const LADDER = [
    "--type-micro",
    "--type-small",
    "--type-body",
    "--type-lede",
    "--type-h3",
    "--type-h2",
    "--type-stat",
    "--type-display",
] as const;

// A clamp() resolves to its first argument at the narrowest viewport, which is
// the size the ladder has to hold at.
const smallestRem = (value: string): number => {
    const match = /(-?\d*\.?\d+)rem/.exec(value);
    if (!match) throw new Error(`no rem value in "${value}"`);
    return Number(match[1]);
};

const baseBlock = (css: string): string => {
    const opener = /^\[data-theme="[a-z0-9-]+"\] \{/m.exec(css);
    if (!opener) throw new Error("no base block");
    return css.slice(opener.index, css.indexOf("\n}", opener.index));
};

const scaleOf = (css: string): { token: string; rem: number }[] => {
    const block = baseBlock(css);
    return LADDER.map((token) => {
        const match = new RegExp(`\\n\\s*${token}:\\s*([^;]+);`).exec(block);
        if (!match) throw new Error(`${token} is not declared in the base block`);
        return { token, rem: smallestRem(match[1]) };
    });
};

describe("type ladder", () => {
    for (const file of THEME_FILES) {
        it(`${file} steps up by at least ${MIN_STEP_RATIO}x from one size to the next`, () => {
            const scale = scaleOf(readFileSync(resolve(THEMES_DIR, file), "utf8"));

            const shortfalls = scale.flatMap((step, i) => {
                const below = scale[i - 1];
                if (!below) return [];
                const ratio = step.rem / below.rem;
                if (ratio >= MIN_STEP_RATIO) return [];
                return [
                    `${step.token} (${step.rem}rem) is only ${ratio.toFixed(3)}x ${below.token} (${below.rem}rem), below the ${MIN_STEP_RATIO}x floor`,
                ];
            });

            expect(shortfalls).toEqual([]);
        });
    }
});
