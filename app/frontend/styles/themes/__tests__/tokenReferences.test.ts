import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative, resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { THEME_FILES, THEMES_DIR } from "app/frontend/styles/themes/__tests__/themeFiles";
const COMPONENTS_DIR = resolve(__dirname, "../../../components");
const STYLES_DIR = resolve(__dirname, "../..");
const REPO_ROOT = resolve(__dirname, "../../../../..");
const FRONTEND_DIR = resolve(__dirname, "../../..");
const EXTRACT_TOKENS_SCRIPT = resolve(REPO_ROOT, "scripts/extract_sway_tokens.mjs");
const TOKENS_CSS = resolve(THEMES_DIR, "..", "tokens.css");

// @lat: [[theme-test-suite-silent-failure-guards#Token references: var(--typo) fails nowhere]]
// @lat: [[theme-tokens#Why a token in the contract has to have a consumer]]

const filesUnder = (dir: string, predicate: (path: string) => boolean): string[] =>
    readdirSync(dir).flatMap((entry) => {
        const path = join(dir, entry);
        if (statSync(path).isDirectory()) return filesUnder(path, predicate);
        return predicate(path) ? [path] : [];
    });

const cssFilesUnder = (dir: string): string[] => filesUnder(dir, (path) => path.endsWith(".css"));

// @lat: [[theme-tokens#Why the dead-reference check reads app/frontend/styles too]]
const DECLARING_FILES = new Set([TOKENS_CSS, ...THEME_FILES.map((file) => join(THEMES_DIR, file))]);

const consumingCssFiles = (): string[] =>
    [...cssFilesUnder(COMPONENTS_DIR), ...cssFilesUnder(STYLES_DIR)].filter((path) => !DECLARING_FILES.has(path));

const sourceFilesUnder = (dir: string): string[] =>
    filesUnder(dir, (path) => path.endsWith(".ts") || path.endsWith(".tsx"));

const declaredIn = (css: string): Set<string> => new Set(css.match(/--[a-z0-9-]+(?=\s*:)/g) ?? []);

const referencedIn = (css: string): Set<string> =>
    new Set((css.match(/var\(\s*--[a-z0-9-]+/g) ?? []).map((match) => match.replace(/var\(\s*/, "")));

// @lat: [[theme-tokens#Why a token in the contract has to have a consumer]]
const arbitraryValueTokensIn = (src: string): Set<string> =>
    new Set((src.match(/\(--[a-z0-9-]+\)/g) ?? []).map((match) => match.slice(1, -1)));

// @lat: [[theme-tokens#Why a token in the contract has to have a consumer]]
const mobileConsumedTokens = (): Set<string> => {
    const script = readFileSync(EXTRACT_TOKENS_SCRIPT, "utf8");
    const match = /const TOKEN_KEYS = \[([\s\S]*?)\];/.exec(script);
    if (!match) throw new Error(`could not find TOKEN_KEYS in ${EXTRACT_TOKENS_SCRIPT}`);
    return new Set((match[1].match(/"([a-z0-9-]+)"/g) ?? []).map((literal) => `--${literal.slice(1, -1)}`));
};

describe("theme token references", () => {
    // Every variable any theme declares, in any of its blocks. A variable only
    // some themes carry is still fine to use — the rule that uses it just does
    // nothing under the themes that leave it out, which is a design choice.
    const declared = new Set<string>();
    for (const file of THEME_FILES) {
        for (const token of declaredIn(readFileSync(join(THEMES_DIR, file), "utf8"))) {
            declared.add(token);
        }
    }
    // @lat: [[theme-tokens#Why density and motion belong to the theme]]
    for (const token of declaredIn(readFileSync(TOKENS_CSS, "utf8"))) {
        declared.add(token);
    }

    it("has a non-empty token vocabulary to check against", () => {
        expect(declared.size).toBeGreaterThan(50);
    });

    for (const path of consumingCssFiles()) {
        const name = relative(REPO_ROOT, path);

        it(`${name} references only tokens a theme declares`, () => {
            const css = readFileSync(path, "utf8");
            // A stylesheet may declare and use variables of its own (say a
            // component's private --offset); those are not theme variables.
            const locals = declaredIn(css);
            const dead = [...referencedIn(css)].filter((token) => !declared.has(token) && !locals.has(token));

            expect(dead).toEqual([]);
        });
    }
});

// @lat: [[theme-tokens#Why a token in the contract has to have a consumer]]
describe("theme token orphans — every declared token has a consumer", () => {
    const declared = new Set<string>();
    for (const file of THEME_FILES) {
        for (const token of declaredIn(readFileSync(join(THEMES_DIR, file), "utf8"))) {
            declared.add(token);
        }
    }

    const consumed = new Set<string>();
    for (const path of cssFilesUnder(FRONTEND_DIR)) {
        for (const token of referencedIn(readFileSync(path, "utf8"))) consumed.add(token);
    }
    for (const path of sourceFilesUnder(FRONTEND_DIR)) {
        for (const token of arbitraryValueTokensIn(readFileSync(path, "utf8"))) consumed.add(token);
    }
    for (const token of mobileConsumedTokens()) consumed.add(token);

    it("every theme-declared token has at least one consumer", () => {
        const orphans = [...declared].filter((token) => !consumed.has(token)).sort();
        expect(orphans).toEqual([]);
    });
});

// @lat: [[theme-tokens#Why a token in the contract has to have a consumer]]
describe("CSS @utility orphans — every declared utility is used as a class", () => {
    const APPLICATION_CSS = resolve(FRONTEND_DIR, "styles/application.css");
    const applicationCss = readFileSync(APPLICATION_CSS, "utf8");
    const utilities = [...applicationCss.matchAll(/^@utility ([a-z0-9-]+)/gm)].map((match) => match[1]);

    it("has a non-empty utility vocabulary to check against", () => {
        expect(utilities.length).toBeGreaterThan(0);
    });

    // @lat: [[theme-tokens#Why a token in the contract has to have a consumer]]
    const haystacks = [
        ...cssFilesUnder(FRONTEND_DIR).filter((path) => path !== APPLICATION_CSS),
        ...sourceFilesUnder(FRONTEND_DIR),
    ].map((path) => readFileSync(path, "utf8"));

    it("every @utility name is used as a class somewhere outside its declaration", () => {
        const orphans = utilities.filter((name) => {
            const usedSomewhere = haystacks.some((text) => new RegExp(`\\b${name}\\b`).test(text));
            return !usedSomewhere;
        });

        expect(orphans).toEqual([]);
    });
});

// @lat: [[theme-tokens#Why navigation shell and secondary pages use token-driven borders]]
describe("navigation shell & secondary pages — zero hardcoded borders or translate hovers", () => {
    const ALIGNED_FILES = [
        "components/drawer/Drawer.tsx",
        "components/ui/LocaleSelect.tsx",
        "components/ui/button.tsx",
        "components/ui/dialog.tsx",
        "components/ui/sheet.tsx",
        "pages/Legislator.tsx",
        "components/legislators/history/LegislatorTermCard.tsx",
        "components/legislators/history/LegislatorHistoryTermsPanel.tsx",
        "components/legislators/history/HistoricalRepairModal.tsx",
        "pages/Organizations.tsx",
        "pages/Organization.tsx",
        "components/organizations/OrganizationCard.tsx",
        "components/bill/BillContent.tsx",
        "pages/public/Sms.tsx",
    ];

    const FORBIDDEN_TOKENS = [
        /\bborder-2\b/,
        /\bborder-l-2\b/,
        /\bhover:-translate-x-0\.5\b/,
        /\bhover:-translate-y-0\.5\b/,
    ];

    it.each(ALIGNED_FILES)("%s contains no hardcoded border-2, border-l-2, or diagonal hover translations", (file) => {
        const fullPath = resolve(FRONTEND_DIR, file);
        const content = readFileSync(fullPath, "utf8");
        for (const pattern of FORBIDDEN_TOKENS) {
            expect(content).not.toMatch(pattern);
        }
    });
});
