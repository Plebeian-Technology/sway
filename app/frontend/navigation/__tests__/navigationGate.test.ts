import type { PendingVisit } from "@inertiajs/core";
import { describe, expect, it } from "vitest";

import { qualifiesForDim, qualifiesForPlaceholder } from "app/frontend/navigation/navigationGate";
import { pendingVisitFixture } from "app/frontend/navigation/__tests__/pendingVisitFixture";

// @lat: [[navigation-placeholder-tracer#Why navigationGate.test.ts's mutation check defines a second predicate locally]]

const CURRENT_HREF = "https://sway.test/bills";

interface IRow {
    name: string;
    overrides: Partial<PendingVisit>;
    currentHref?: string;
    expectPlaceholder: boolean;
    expectDim: boolean;
}

const rows: IRow[] = [
    {
        name: "Link click / keyboard GET (<Link href>)",
        overrides: { url: new URL("https://sway.test/bills/1") },
        expectPlaceholder: true,
        expectDim: true,
    },
    {
        name: "Programmatic router.visit(href) with no options (Notifications, BillCreatorShell, UserOrganizationMembership, NewPositionDialog)",
        overrides: { url: new URL("https://sway.test/notifications") },
        expectPlaceholder: true,
        expectDim: true,
    },
    {
        name: "Programmatic router.visit with preserveState: true",
        overrides: { url: new URL("https://sway.test/notifications"), preserveState: true },
        expectPlaceholder: false,
        expectDim: false,
    },
    {
        name: "Locale switch — BillOfTheMonth.tsx (useSwayLocale() with no args, query-only href change) — condition 6 compares full href, not pathname",
        overrides: { url: new URL("https://sway.test/bill_of_the_month?sway_locale_id=2"), preserveState: false },
        currentHref: "https://sway.test/bill_of_the_month",
        expectPlaceholder: true,
        expectDim: true,
    },
    {
        name: "Locale switch — Bills.tsx (useSwayLocale(LOCALE_SWITCH_PROPS), only non-empty + preserveState true)",
        overrides: {
            url: new URL("https://sway.test/bills?sway_locale_id=2"),
            only: ["bills", "bills_total", "all_categories", "sway_locale"],
            preserveState: true,
        },
        currentHref: "https://sway.test/bills",
        expectPlaceholder: false,
        expectDim: false,
    },
    {
        name: "Locale switch — Legislators.tsx (only non-empty + preserveState true)",
        overrides: {
            url: new URL("https://sway.test/legislators?sway_locale_id=2"),
            only: ["legislators", "sway_locale"],
            preserveState: true,
        },
        currentHref: "https://sway.test/legislators",
        expectPlaceholder: false,
        expectDim: false,
    },
    {
        name: "Locale switch — Influence.tsx (only non-empty + preserveState true)",
        overrides: {
            url: new URL("https://sway.test/influence?sway_locale_id=2"),
            only: ["influence", "sway_locale"],
            preserveState: true,
        },
        currentHref: "https://sway.test/influence",
        expectPlaceholder: false,
        expectDim: false,
    },
    {
        name: "Score sync 15s — useScoreSubscription (router.reload({ only: onlyProps }))",
        overrides: { only: ["bill_score"], async: true, preserveState: true },
        expectPlaceholder: false,
        expectDim: false,
    },
    {
        name: "usePoll 15s/5s — Bill, BillOfTheMonth, Legislators, Organizations, Organization, LlmSettings, BillCreatorSummary, BillCreatorPositions, BillCreatorPipelineLlm, PipelineRuns/Index (doReload)",
        overrides: { only: ["some_prop"], async: true, preserveState: true },
        expectPlaceholder: false,
        expectDim: false,
    },
    {
        name: "Bill Creator poll 5s and registration poll 3s (doReload, {only, async: true, preserveState: true})",
        overrides: { only: ["user", "processing"], async: true, preserveState: true },
        expectPlaceholder: false,
        expectDim: false,
    },
    {
        name: "Bare pull-to-refresh reload — Bill.tsx:41, BillOfTheMonth.tsx:42 (only empty, async true, preserveState true) — conditions 3 and 5 are the only ones that catch it",
        overrides: { only: [], async: true, preserveState: true, url: new URL("https://sway.test/bills/1") },
        expectPlaceholder: false,
        expectDim: false,
    },
    {
        name: "Hover prefetch request itself (prefetch true, async true) — excluded by conditions 2 and 3",
        overrides: { prefetch: true, async: true, url: new URL("https://sway.test/legislators") },
        expectPlaceholder: false,
        expectDim: false,
    },
    {
        name: "A click that consumes a cached or in-flight prefetch (ordinary GET shape, no start/finish)",
        overrides: { url: new URL("https://sway.test/legislators") },
        expectPlaceholder: true,
        expectDim: true,
    },
    {
        name: "RunSelector.tsx router.get(..., { only: RUN_SELECTOR_ONLY_PROPS, preserveState: true })",
        overrides: {
            only: ["pipeline_run_stages"],
            preserveState: true,
            url: new URL("https://sway.test/pipeline_runs?run_id=1"),
        },
        currentHref: "https://sway.test/pipeline_runs",
        expectPlaceholder: false,
        expectDim: false,
    },
    {
        name: "Bills.tsx category toggle / clear / load-more (GET partial, preserveState true)",
        overrides: { only: ["bills"], preserveState: true, url: new URL("https://sway.test/bills?category=1") },
        currentHref: "https://sway.test/bills",
        expectPlaceholder: false,
        expectDim: false,
    },
    {
        name: "useDebouncedUrlSearch / useUrlSort (GET partial, preserveState true)",
        overrides: { only: ["bills"], preserveState: true, url: new URL("https://sway.test/bills?q=foo") },
        currentHref: "https://sway.test/bills",
        expectPlaceholder: false,
        expectDim: false,
    },
    {
        name: "Any POST/PUT/PATCH/DELETE (form submission — non-GET visit)",
        overrides: { method: "post", preserveState: true, url: new URL("https://sway.test/bills") },
        currentHref: "https://sway.test/bills/new",
        expectPlaceholder: false,
        expectDim: false,
    },
    {
        name: "Inertia's own missingHistoryItem recovery visit (GET, only empty, preserveState true, same href)",
        overrides: { only: [], preserveState: true, url: new URL(CURRENT_HREF) },
        expectPlaceholder: false,
        expectDim: false,
    },
    {
        name: "Exact self-navigation to the current href",
        overrides: { url: new URL(CURRENT_HREF) },
        expectPlaceholder: false,
        expectDim: false,
    },
    {
        name: "Drop of a fragment — <Link href='/bills'> while the reader is on /bills#top",
        overrides: { url: new URL("https://sway.test/bills") },
        currentHref: "https://sway.test/bills#top",
        expectPlaceholder: false,
        expectDim: false,
    },
    {
        name: "In-page anchor — <Link href='/bills#section'> while the reader is on /bills",
        overrides: { url: new URL("https://sway.test/bills#section") },
        currentHref: "https://sway.test/bills",
        expectPlaceholder: false,
        expectDim: false,
    },
    {
        name: "Fragment on a genuinely different path still qualifies",
        overrides: { url: new URL("https://sway.test/legislators#top") },
        currentHref: "https://sway.test/bills",
        expectPlaceholder: true,
        expectDim: true,
    },
];

describe.each(rows)("$name", ({ overrides, currentHref, expectPlaceholder, expectDim }) => {
    const visit = pendingVisitFixture(overrides);
    const href = currentHref ?? CURRENT_HREF;

    it(`qualifiesForPlaceholder is ${expectPlaceholder}`, () => {
        expect(qualifiesForPlaceholder(visit, href)).toBe(expectPlaceholder);
    });

    it(`qualifiesForDim is ${expectDim}`, () => {
        expect(qualifiesForDim(visit, href)).toBe(expectDim);
    });
});

describe("mutation check — condition 3 (async) is load-bearing, not belt and braces", () => {
    const withoutAsyncCondition = (visit: PendingVisit, currentHref: string): boolean =>
        visit.only.length === 0 &&
        visit.except.length === 0 &&
        visit.prefetch === false &&
        visit.method === "get" &&
        visit.preserveState !== true &&
        visit.url.href !== currentHref;

    it("flips a background-reload-shaped visit to qualifying once the async condition is removed, where the real predicate excludes it", () => {
        const visit = pendingVisitFixture({
            only: [],
            async: true,
            preserveState: false,
            url: new URL("https://sway.test/bills/1"),
        });

        expect(withoutAsyncCondition(visit, CURRENT_HREF)).toBe(true);
        expect(qualifiesForPlaceholder(visit, CURRENT_HREF)).toBe(false);
    });
});
