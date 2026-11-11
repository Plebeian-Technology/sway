import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { describe, expect, it } from "vitest";

import { THEME_NAMES, themeCss } from "app/frontend/styles/themes/__tests__/themeFiles";

// @lat: [[theme-tokens#Why the chart label gutter is a theme token]]
const WIDEST_DISTRICT_LABEL_PX: Record<string, number> = {
    ballot: 86.05,
    banner: 83.5,
    cornerstore: 88.65,
    monochrome: 78.5,
    "service-manual": 76.8,
    "swiss-grid": 81.2,
    sway: 71.36,
};

const ROOT_FONT_SIZE_PX = 16;

const CHART_FILES = [
    "app/frontend/components/bill/charts/DistrictVotesChart.tsx",
    "app/frontend/components/bill/charts/AffinityDistrictChart.tsx",
];

const gutterRemFor = (theme: string): number => {
    const match = themeCss(theme).match(/--chart-label-gutter:\s*([\d.]+)rem;/);
    expect(match, `${theme}.css declares --chart-label-gutter in rem`).not.toBeNull();
    return Number(match![1]);
};

describe("the chart label gutter", () => {
    it("is declared by every theme", () => {
        for (const theme of THEME_NAMES) {
            expect(themeCss(theme)).toContain("--chart-label-gutter:");
        }
    });

    it.each(THEME_NAMES)("%s leaves room for the widest district label it can render", (theme) => {
        const widest = WIDEST_DISTRICT_LABEL_PX[theme];
        expect(widest, `${theme} has no recorded label measurement`).toBeGreaterThan(0);

        expect(gutterRemFor(theme) * ROOT_FONT_SIZE_PX).toBeGreaterThanOrEqual(widest);
    });

    it.each(CHART_FILES)("%s sizes its label column from the token, not a rem literal", (file) => {
        const source = readFileSync(resolve(process.cwd(), file), "utf8");
        const templates = source.match(/grid-cols-\[[^\]]*\]/g) ?? [];

        expect(templates.length, `expected a grid template in ${file}`).toBeGreaterThan(0);

        for (const template of templates) {
            expect(template).toContain("var(--chart-label-gutter)");
            expect(template).not.toMatch(/\[[\d.]+rem_/);
        }
    });
});
