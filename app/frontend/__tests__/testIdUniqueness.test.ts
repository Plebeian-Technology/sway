/**
 // @lat: [[testid-uniqueness-test-design#Why SAME_FILE_BRANCHES exists, one level in from MUTUALLY_EXCLUSIVE]]
 */

import { readdirSync, readFileSync } from "fs";
import { join } from "path";
import { describe, expect, it } from "vitest";

const FRONTEND_ROOT = join(process.cwd(), "app", "frontend");

/**
 // @lat: [[testid-uniqueness-test-design#Why MUTUALLY_EXCLUSIVE names the guaranteeing function]]
 */
const MUTUALLY_EXCLUSIVE: Record<string, string> = {
    // billListLayoutFor() in components/bill/list-layouts/index.ts returns
    // exactly one list layout per active theme.
    "btn-load-more-bills": "one bill-list layout per theme (billListLayoutFor)",
    // billLayoutFor() in components/bill/layouts/index.ts returns exactly one
    // bill-detail layout per theme, and each mounts exactly one vote panel.
    "vote-recorded": "one bill-detail layout per theme (billLayoutFor)",
    "vote-announcement": "one bill-detail layout per theme (billLayoutFor)",
    // @lat: [[testid-uniqueness-test-design#The BillHeader entry]]
    "bill-title": "one bill-detail layout per theme (billLayoutFor)",
    "score-panel": "one bill-detail layout per theme (billLayoutFor)",
    "legislator-comparison": "one bill-detail layout per theme (billLayoutFor)",
    "no-source-link": "one bill-detail layout per theme (billLayoutFor)",
    "provisional-vote-banner": "one bill-detail layout per theme (billLayoutFor)",
    "legislators-count-line": "one legislators layout per theme (legislatorsLayoutFor)",
    "legislators-term-year-range": "one legislators layout per theme (legislatorsLayoutFor)",
    "legislators-history-tab": "one legislators layout per theme (legislatorsLayoutFor)",
    "legislators-history-error": "one legislators layout per theme (legislatorsLayoutFor)",
    "legislators-history-retry-button": "one legislators layout per theme (legislatorsLayoutFor)",
    "legislators-history-empty": "one legislators layout per theme (legislatorsLayoutFor)",
};

/**
 // @lat: [[testid-uniqueness-test-design#Why SAME_FILE_BRANCHES exists, one level in from MUTUALLY_EXCLUSIVE]]
 */
const SAME_FILE_BRANCHES: Record<string, { file: string; sites: number }> = {
    "ai-unreviewed-notice": { file: "app/frontend/components/bill/AiUnreviewedNotice.tsx", sites: 2 },
    // @lat: [[testid-uniqueness-test-design#The status-pill entry's count]]
    "llm-status-badge": { file: "app/frontend/components/admin/creator/BillCreatorLlmSummaryBadge.tsx", sites: 7 },
    // @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#What the tab says about a run it did not finish]]
    "pipeline-status-badge": {
        file: "app/frontend/components/admin/creator/BillCreatorPipelineStatusBadge.tsx",
        sites: 10,
    },
    "bill-pipeline-status-badge": {
        file: "app/frontend/components/admin/creator/BillCreatorPipelineStatusBadge.tsx",
        sites: 10,
    },
    // One return for the empty state and another for the filled one, both using
    // the same wrapper element, so tests can find the id either way.
    "fetched-bills-panel": { file: "app/frontend/components/admin/creator/FetchedBillsPanel.tsx", sites: 2 },
    // @lat: [[campaign-position-cards#Approving a campaign out of testimony#Why a decision is read back onto the card]]
    "campaign-position-card-${}": {
        file: "app/frontend/components/admin/creator/BillCreatorCampaignPositionCard.tsx",
        sites: 3,
    },
    "btn-restore-campaign-position": {
        file: "app/frontend/components/admin/creator/BillCreatorCampaignPositionCard.tsx",
        sites: 2,
    },
    "notification-push-toggle": { file: "app/frontend/components/notifications/PushNotificationsPanel.tsx", sites: 2 },
    "org-membership-accepted": { file: "app/frontend/components/organizations/PendingChangesList.tsx", sites: 2 },
    "per-bill-grid": { file: "app/frontend/components/admin/creator/PerBillGrid.tsx", sites: 2 },
    "pipeline-progress": { file: "app/frontend/components/admin/creator/PipelineProgress.tsx", sites: 2 },
    "positions-tab": { file: "app/frontend/components/admin/creator/BillCreatorPositions.tsx", sites: 2 },
    "summary-tab": { file: "app/frontend/components/admin/creator/BillCreatorSummary.tsx", sites: 2 },
    // Two returns inside ONE map callback (a cached row, or "Not cached"), so
    // only one of them runs each time round. The ids actually rendered differ
    // from one pass to the next anyway (tier-row-<tier>); they only look like a
    // single value because this file rewrites every ${...} to a plain ${}.
    "tier-row-${}": { file: "app/frontend/components/admin/creator/ResourceCachePanel.tsx", sites: 2 },
    "news-article-testimony": { file: "app/frontend/components/bill/NewsArticleTestimony.tsx", sites: 7 },
    "related-news-articles": { file: "app/frontend/components/bill/RelatedNewsArticles.tsx", sites: 7 },
};

const collectSourceFiles = (dir: string, acc: string[] = []): string[] => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
        const full = join(dir, entry.name);
        if (entry.isDirectory()) {
            // __tests__/ vi.mock stand-ins copy the ids of the components they replace.
            if (entry.name === "__tests__") continue;
            collectSourceFiles(full, acc);
        } else if (/\.tsx?$/.test(entry.name)) {
            acc.push(full);
        }
    }
    return acc;
};

/**
 // @lat: [[testid-uniqueness-test-design#Why the same data-testid on two components is a bug]]
 */
const TESTID_ATTRIBUTES = ["data-testid", "testId", "dataTestid"];

/**
 // @lat: [[testid-uniqueness-test-design#Why testIdUniqueness.test.ts exists and how its allowlists work]]
 */
const extractTestIds = (source: string): { value: string; line: number }[] => {
    const found: { value: string; line: number }[] = [];
    const attribute = new RegExp(`\\b(?:${TESTID_ATTRIBUTES.join("|")})\\s*=\\s*`, "g");
    let match: RegExpExecArray | null;

    const literalsIn = (text: string): string[] =>
        [...text.matchAll(/"([^"]*)"|`([^`]*)`/g)].map((literal) =>
            (literal[1] ?? literal[2]).replace(/\$\{[^}]*\}/g, "${}"),
        );

    // For `const x = <value>;`, the value runs up to the first semicolon at the
    // outermost level, which is enough for the ternaries written here.
    const constInitializer = (name: string): string | null => {
        const declaration = new RegExp(`\\bconst\\s+${name}\\s*(?::[^=]*)?=\\s*`).exec(source);
        if (!declaration) return null;
        const start = declaration.index + declaration[0].length;
        const end = source.indexOf(";", start);
        if (end === -1) return null;
        // Throw away the strings being compared against. In
        // `const testId = scope === "bill" ? "a" : "b"` the ids are "a" and
        // "b"; "bill" is only what the check compares to.
        return source.slice(start, end).replace(/[=!]==?\s*(?:"[^"]*"|`[^`]*`)/g, "");
    };

    while ((match = attribute.exec(source)) !== null) {
        const start = match.index + match[0].length;
        const line = source.slice(0, start).split("\n").length;

        if (source[start] === '"') {
            found.push({ value: source.slice(start + 1, source.indexOf('"', start + 1)), line });
            continue;
        }
        if (source[start] !== "{") continue;

        let depth = 0;
        let end = start;
        for (; end < source.length; end += 1) {
            if (source[end] === "{") depth += 1;
            else if (source[end] === "}") {
                depth -= 1;
                if (depth === 0) break;
            }
        }
        const expression = source.slice(start + 1, end).trim();
        const literals = literalsIn(expression);
        if (literals.length) {
            for (const value of literals) found.push({ value, line });
            continue;
        }

        const identifier = /^[A-Za-z_$][\w$]*$/.test(expression) ? expression : null;
        if (!identifier) continue;
        const initializer = constInitializer(identifier);
        if (!initializer) continue;
        for (const value of literalsIn(initializer)) found.push({ value, line });
    }
    return found;
};

describe("data-testid uniqueness across production components", () => {
    // @lat: [[testid-uniqueness-test-design#Why occurrences are counted per file, not just tracked as "more than one file"]]
    const owners = new Map<string, Map<string, number>>();

    for (const file of collectSourceFiles(FRONTEND_ROOT)) {
        const relative = file.replace(`${process.cwd()}/`, "");
        for (const { value } of extractTestIds(readFileSync(file, "utf-8"))) {
            // Something like `data-testid={props["data-testid"]}` is only
            // passing an id along; it has none of its own.
            if (!value || value === "data-testid") continue;
            if (!owners.has(value)) owners.set(value, new Map());
            const byFile = owners.get(value)!;
            byFile.set(relative, (byFile.get(relative) ?? 0) + 1);
        }
    }

    const filesFor = (value: string) => new Set(owners.get(value)?.keys() ?? []);

    it("finds testids to check (guards against the sweep silently matching nothing)", () => {
        expect(owners.size).toBeGreaterThan(100);
    });

    it("has no testid rendered by two components outside the mutually-exclusive allowlist", () => {
        const offenders = [...owners]
            // Object.hasOwn, not `value in`. `in` also finds properties every
            // JavaScript object inherits, so a test id named "constructor",
            // "toString", or "valueOf" was quietly let through.
            .filter(([value, byFile]) => byFile.size > 1 && !Object.hasOwn(MUTUALLY_EXCLUSIVE, value))
            .map(([value, byFile]) => `${value} -> ${[...byFile.keys()].sort().join(", ")}`)
            .sort();

        expect(offenders).toEqual([]);
    });

    // @lat: [[testid-uniqueness-test-design#Why both allowlists needed the same safe-lookup fix]]
    const INHERITED_NAMES = ["constructor", "toString", "valueOf", "hasOwnProperty"];

    // The unsafe lookup, named once so the examples below can demonstrate the
    // hazard without writing the form the source check bans.
    const unsafeLookup = (map: object, key: string) => key in map;

    it("exempts only allowlisted values, and does not inherit exemptions from Object.prototype", () => {
        for (const inherited of INHERITED_NAMES) {
            // Both halves matter. The first says the hazard is real: ask either
            // map about these names the unsafe way and it says yes, though
            // nobody listed them. The second says the lookup the sweep really
            // uses refuses them anyway.
            expect(unsafeLookup(MUTUALLY_EXCLUSIVE, inherited)).toBe(true);
            expect(unsafeLookup(SAME_FILE_BRANCHES, inherited)).toBe(true);
            expect(Object.hasOwn(MUTUALLY_EXCLUSIVE, inherited)).toBe(false);
            expect(Object.hasOwn(SAME_FILE_BRANCHES, inherited)).toBe(false);
        }
    });

    // @lat: [[testid-uniqueness-test-design#Why the unsafe-lookup guard reads the file's own text]]
    it("looks both allowlists up with Object.hasOwn, never with the inherited-key form", () => {
        const code = readFileSync(__filename, "utf-8")
            .split("\n")
            .filter((line) => !/^\s*(\/\/|\*|\/\*)/.test(line))
            .join("\n");

        expect(code.match(/\bin\s+(MUTUALLY_EXCLUSIVE|SAME_FILE_BRANCHES)\b/g) ?? []).toEqual([]);
    });

    // @lat: [[testid-uniqueness-test-design#Why the within-one-component check has its own explanation of the branch rule]]
    it("has no testid assigned twice within one component outside the recorded branch sets", () => {
        const offenders = [...owners]
            .flatMap(([value, byFile]) =>
                [...byFile]
                    .filter(([file, count]) => {
                        if (count <= 1) return false;
                        const recorded = Object.hasOwn(SAME_FILE_BRANCHES, value)
                            ? SAME_FILE_BRANCHES[value]
                            : undefined;
                        return recorded?.file !== file || recorded.sites !== count;
                    })
                    .map(([file, count]) => `${value} -> ${file} (${count} sites)`),
            )
            .sort();

        expect(offenders).toEqual([]);
    });

    // Keeps the list from going stale, the way MUTUALLY_EXCLUSIVE already does:
    // an exception whose repeat is gone must be deleted, so the list only
    // shrinks.
    it("records no same-file exemption that is no longer duplicated", () => {
        for (const [value, { file, sites }] of Object.entries(SAME_FILE_BRANCHES)) {
            expect(owners.get(value)?.get(file) ?? 0, `${value} in ${file} no longer has ${sites} sites`).toBe(sites);
        }
    });

    // Both of these are set as `data-testid={testId}` from a local const, and
    // neither appeared in anything this file built until the scanner learned to
    // follow a variable to its value.
    it("sees the ids assigned through a local variable (C1-i6-IN-01)", () => {
        const badge = "app/frontend/components/admin/creator/BillCreatorPipelineStatusBadge.tsx";
        expect(filesFor("pipeline-status-badge")).toEqual(new Set([badge]));
        expect(filesFor("bill-pipeline-status-badge")).toEqual(new Set([badge]));
    });

    // And these five are set through a prop with a different name (`testId=`)
    // on a local wrapper, which a scan for `data-testid` alone could not see
    // either.
    it("sees the ids assigned through a differently-named prop (C1-i6-IN-01)", () => {
        for (const value of [
            "legislator-detail-district",
            "legislator-detail-email",
            "legislator-detail-phone",
            "legislator-detail-twitter",
            "legislator-detail-link",
        ]) {
            expect(filesFor(value)).toEqual(new Set(["app/frontend/pages/Legislator.tsx"]));
        }
    });

    it("finds no follower count on any surface", () => {
        expect(filesFor("org-card-follower-count-${}")).toEqual(new Set());
        expect(filesFor("org-detail-follower-count")).toEqual(new Set());
    });

    it("still exempts only allowlisted values that are actually duplicated", () => {
        for (const value of Object.keys(MUTUALLY_EXCLUSIVE)) {
            expect(owners.get(value)?.size ?? 0).toBeGreaterThan(1);
        }
    });
});
