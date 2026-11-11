// @lat: [[query-parameter-navigation-carry#Centralized interception mechanism]]
// @lat: [[query-parameter-navigation-carry#Excluded route constants and security boundaries]]
// @lat: [[query-parameter-navigation-carry#The cleared-on-purpose signal]]

import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { http, router, type PendingVisit } from "@inertiajs/core";
import {
    applyNavigationCarryToVisit,
    registerQueryParamNavigationCarry,
    unregisterQueryParamNavigationCarry,
    isNavigationCarryRegistered,
} from "app/frontend/sway_utils/queryParamNavigationCarry";
import { setQueryParamCleared } from "app/frontend/sway_utils/queryParamClearedSignal";

describe("queryParamNavigationCarry", () => {
    describe("applyNavigationCarryToVisit", () => {
        it("carries global ambient parameters (sway_locale_id, run_id, highlight_bill_id) across routes", () => {
            const visit = {
                url: new URL("https://sway.test/legislators"),
                method: "get",
                data: {},
            } as unknown as PendingVisit;

            applyNavigationCarryToVisit(visit, {
                currentUrl: "https://sway.test/bills?sway_locale_id=42&run_id=99&highlight_bill_id=500",
            });

            const resultUrl = visit.url as URL;
            expect(resultUrl.searchParams.get("sway_locale_id")).toBe("42");
            expect(resultUrl.searchParams.get("run_id")).toBe("99");
            expect(resultUrl.searchParams.get("highlight_bill_id")).toBe("500");
        });

        it("carries feature-specific parameters within the feature boundary", () => {
            const visit = {
                url: new URL("https://sway.test/bills?bills_page=2"),
                method: "get",
                data: {},
            } as unknown as PendingVisit;

            applyNavigationCarryToVisit(visit, {
                currentUrl: "https://sway.test/bills?bills_sort=title&bills_direction=asc&sway_locale_id=1",
            });

            const resultUrl = visit.url as URL;
            expect(resultUrl.searchParams.get("bills_sort")).toBe("title");
            expect(resultUrl.searchParams.get("bills_direction")).toBe("asc");
            expect(resultUrl.searchParams.get("bills_page")).toBe("2");
            expect(resultUrl.searchParams.get("sway_locale_id")).toBe("1");
        });

        it("does not leak feature parameters across feature boundaries", () => {
            const visit = {
                url: new URL("https://sway.test/legislators"),
                method: "get",
                data: {},
            } as unknown as PendingVisit;

            applyNavigationCarryToVisit(visit, {
                currentUrl: "https://sway.test/bills?bills_sort=title&sway_locale_id=1",
            });

            const resultUrl = visit.url as URL;
            expect(resultUrl.searchParams.has("bills_sort")).toBe(false);
            expect(resultUrl.searchParams.get("sway_locale_id")).toBe("1");
        });

        it("does not carry parameters to excluded routes", () => {
            const excludedPaths = [
                "/api/v1/bills",
                "/api/internal/status",
                "/sessions/new",
                "/passkeys",
                "/registrations",
                "/phone_verification",
                "/sway_registration",
                "/users/webauthn/login",
                "/users/passkeys/create",
            ];

            for (const path of excludedPaths) {
                const visit = {
                    url: new URL(`https://sway.test${path}`),
                    method: "get",
                    data: {},
                } as unknown as PendingVisit;

                applyNavigationCarryToVisit(visit, {
                    currentUrl: "https://sway.test/bills?sway_locale_id=1&run_id=5&bills_sort=title",
                });

                const resultUrl = visit.url as URL;
                expect(resultUrl.searchParams.has("sway_locale_id")).toBe(false);
                expect(resultUrl.searchParams.has("run_id")).toBe(false);
                expect(resultUrl.searchParams.has("bills_sort")).toBe(false);
                expect(resultUrl.search).toBe("");
            }
        });

        it("does not carry unregistered ephemeral parameters", () => {
            const visit = {
                url: new URL("https://sway.test/bills"),
                method: "get",
                data: {},
            } as unknown as PendingVisit;

            applyNavigationCarryToVisit(visit, {
                currentUrl: "https://sway.test/bills?unknown_param=val&sway_locale_id=1",
            });

            const resultUrl = visit.url as URL;
            expect(resultUrl.searchParams.has("unknown_param")).toBe(false);
            expect(resultUrl.searchParams.get("sway_locale_id")).toBe("1");
        });

        it("respects destination URL parameter precedence", () => {
            const visit = {
                url: new URL("https://sway.test/bills?bills_sort=date"),
                method: "get",
                data: {},
            } as unknown as PendingVisit;

            applyNavigationCarryToVisit(visit, {
                currentUrl: "https://sway.test/bills?bills_sort=title&bills_direction=asc",
            });

            const resultUrl = visit.url as URL;
            expect(resultUrl.searchParams.get("bills_sort")).toBe("date");
            expect(resultUrl.searchParams.get("bills_direction")).toBe("asc");
        });

        it("respects visit.data parameter precedence for object data", () => {
            const visit = {
                url: new URL("https://sway.test/bills"),
                method: "get",
                data: { bills_sort: "date" },
            } as unknown as PendingVisit;

            applyNavigationCarryToVisit(visit, {
                currentUrl: "https://sway.test/bills?bills_sort=title&bills_direction=asc",
            });

            const resultUrl = visit.url as URL;
            expect(resultUrl.searchParams.has("bills_sort")).toBe(false);
            expect(resultUrl.searchParams.get("bills_direction")).toBe("asc");
        });

        it("respects visit.data parameter precedence for FormData data", () => {
            const formData = new FormData();
            formData.append("bills_sort", "date");

            const visit = {
                url: new URL("https://sway.test/bills"),
                method: "post",
                data: formData,
            } as unknown as PendingVisit;

            applyNavigationCarryToVisit(visit, {
                currentUrl: "https://sway.test/bills?bills_sort=title&sway_locale_id=1",
            });

            const resultUrl = visit.url as URL;
            expect(resultUrl.searchParams.has("bills_sort")).toBe(false);
            expect(resultUrl.searchParams.get("sway_locale_id")).toBe("1");
        });

        it("does not carry cleared parameters from current URL", () => {
            const visit = {
                url: new URL("https://sway.test/bills"),
                method: "get",
                data: {},
            } as unknown as PendingVisit;

            applyNavigationCarryToVisit(visit, {
                currentUrl: "https://sway.test/bills?run_id=&sway_locale_id=1",
            });

            const resultUrl = visit.url as URL;
            expect(resultUrl.searchParams.has("run_id")).toBe(false);
            expect(resultUrl.searchParams.get("sway_locale_id")).toBe("1");
        });

        it("does not resurrect parameters cleared in destination URL and strips the cleared sentinel", () => {
            const destinationUrl = setQueryParamCleared("https://sway.test/admin/bill_creator/new", "run_id");
            expect(destinationUrl).toContain("run_id=");

            const visit = {
                url: new URL(destinationUrl),
                method: "get",
                data: {},
            } as unknown as PendingVisit;

            applyNavigationCarryToVisit(visit, {
                currentUrl: "https://sway.test/admin/bill_creator/new?run_id=42&sway_locale_id=1",
            });

            const resultUrl = visit.url as URL;
            expect(resultUrl.searchParams.has("run_id")).toBe(false);
            expect(resultUrl.searchParams.get("sway_locale_id")).toBe("1");
        });

        it("carries origin allowed parameters on non-GET visits for server redirect echo", () => {
            const visit = {
                url: new URL("https://sway.test/bills"),
                method: "post",
                data: {},
            } as unknown as PendingVisit;

            applyNavigationCarryToVisit(visit, {
                currentUrl: "https://sway.test/admin/bill_creator/new?bill_creator_tab=summary&run_id=10",
            });

            const resultUrl = visit.url as URL;
            expect(resultUrl.searchParams.get("bill_creator_tab")).toBe("summary");
            expect(resultUrl.searchParams.get("run_id")).toBe("10");
        });

        it("handles string visit.url and normalizes it to URL", () => {
            const visit = {
                url: "/bills" as unknown as URL,
                method: "get",
                data: {},
            } as unknown as PendingVisit;

            applyNavigationCarryToVisit(visit, {
                currentUrl: "https://sway.test/bills?sway_locale_id=7",
            });

            const resultUrl = visit.url as URL;
            expect(resultUrl).toBeInstanceOf(URL);
            expect(resultUrl.searchParams.get("sway_locale_id")).toBe("7");
        });

        it("does not leak foreign legacy aliases across feature boundaries even if destination feature declares an alias with the same name", () => {
            const visit = {
                url: new URL("https://sway.test/legislators"),
                method: "get",
                data: {},
            } as unknown as PendingVisit;

            applyNavigationCarryToVisit(visit, {
                currentUrl: "https://sway.test/bills?search=zoning&sway_locale_id=42",
            });

            const resultUrl = visit.url as URL;
            expect(resultUrl.searchParams.has("search")).toBe(false);
            expect(resultUrl.searchParams.has("legislators_search")).toBe(false);
            expect(resultUrl.searchParams.get("sway_locale_id")).toBe("42");
        });

        it("does not leak legislators search alias into bills", () => {
            const visit = {
                url: new URL("https://sway.test/bills"),
                method: "get",
                data: {},
            } as unknown as PendingVisit;

            applyNavigationCarryToVisit(visit, {
                currentUrl: "https://sway.test/legislators?search=smith&sway_locale_id=42",
            });

            const resultUrl = visit.url as URL;
            expect(resultUrl.searchParams.has("search")).toBe(false);
            expect(resultUrl.searchParams.has("bills_search")).toBe(false);
            expect(resultUrl.searchParams.get("sway_locale_id")).toBe("42");
        });

        it("does not leak legacy tab alias across distinct tabbed features", () => {
            const visit = {
                url: new URL("https://sway.test/notifications"),
                method: "get",
                data: {},
            } as unknown as PendingVisit;

            applyNavigationCarryToVisit(visit, {
                currentUrl: "https://sway.test/legislators?tab=contact",
            });

            const resultUrl = visit.url as URL;
            expect(resultUrl.searchParams.has("tab")).toBe(false);
            expect(resultUrl.searchParams.has("notifications_tab")).toBe(false);
        });

        it("preserves explicit destination legacy alias and suppresses implicitly carried canonical parameter", () => {
            const visit = {
                url: new URL("https://sway.test/bills?search=housing"),
                method: "get",
                data: {},
            } as unknown as PendingVisit;

            applyNavigationCarryToVisit(visit, {
                currentUrl: "https://sway.test/bills?bills_search=zoning",
            });

            const resultUrl = visit.url as URL;
            expect(resultUrl.searchParams.get("search")).toBe("housing");
            expect(resultUrl.searchParams.has("bills_search")).toBe(false);
        });

        it("preserves explicit destination canonical parameter and suppresses implicitly carried legacy alias", () => {
            const visit = {
                url: new URL("https://sway.test/bills?bills_search=housing"),
                method: "get",
                data: {},
            } as unknown as PendingVisit;

            applyNavigationCarryToVisit(visit, {
                currentUrl: "https://sway.test/bills?search=zoning",
            });

            const resultUrl = visit.url as URL;
            expect(resultUrl.searchParams.get("bills_search")).toBe("housing");
            expect(resultUrl.searchParams.has("search")).toBe(false);
        });

        it("preserves destination parameters when destination explicitly supplies both canonical and legacy alias", () => {
            const visit = {
                url: new URL("https://sway.test/bills?bills_search=canonical_choice&search=alias_choice"),
                method: "get",
                data: {},
            } as unknown as PendingVisit;

            applyNavigationCarryToVisit(visit, {
                currentUrl: "https://sway.test/bills?bills_search=old_carried",
            });

            const resultUrl = visit.url as URL;
            expect(resultUrl.searchParams.get("bills_search")).toBe("canonical_choice");
            expect(resultUrl.searchParams.get("search")).toBe("alias_choice");
        });

        it("suppresses carried canonical parameter when visit.data provides explicit legacy alias", () => {
            const visit = {
                url: new URL("https://sway.test/bills"),
                method: "get",
                data: { search: "housing" },
            } as unknown as PendingVisit;

            applyNavigationCarryToVisit(visit, {
                currentUrl: "https://sway.test/bills?bills_search=zoning",
            });

            const resultUrl = visit.url as URL;
            expect(resultUrl.searchParams.has("bills_search")).toBe(false);
        });

        it("carries legacy alias within same feature when destination has no search parameter", () => {
            const visit = {
                url: new URL("https://sway.test/bills?bills_page=2"),
                method: "get",
                data: {},
            } as unknown as PendingVisit;

            applyNavigationCarryToVisit(visit, {
                currentUrl: "https://sway.test/bills?search=zoning",
            });

            const resultUrl = visit.url as URL;
            expect(resultUrl.searchParams.get("search")).toBe("zoning");
            expect(resultUrl.searchParams.get("bills_page")).toBe("2");
        });

        it("does not carry selected_stages[] or selected_stages= when visit.only includes selected_stages and selected_stages is omitted from visit.url and visit.data", () => {
            const visitFromAllStages = {
                url: new URL("https://sway.test/admin/bill_creator/42/pipeline"),
                method: "get",
                data: {},
                only: ["selected_stages", "download_missing_assets", "pipeline_preview"],
            } as unknown as PendingVisit;

            applyNavigationCarryToVisit(visitFromAllStages, {
                currentUrl:
                    "https://sway.test/admin/bill_creator/42/pipeline?selected_stages[]=fetch-bills&selected_stages[]=summarize-bill&run_id=99",
            });

            const resultFromAll = visitFromAllStages.url as URL;
            expect(resultFromAll.searchParams.has("selected_stages")).toBe(false);
            expect(resultFromAll.searchParams.has("selected_stages[]")).toBe(false);
            expect(resultFromAll.searchParams.has("stages")).toBe(false);
            expect(resultFromAll.searchParams.has("stages[]")).toBe(false);
            expect(resultFromAll.searchParams.get("run_id")).toBe("99");

            const visitFromEmptyStages = {
                url: new URL("https://sway.test/admin/bill_creator/42/pipeline"),
                method: "get",
                data: {},
                only: ["selected_stages", "download_missing_assets", "pipeline_preview"],
            } as unknown as PendingVisit;

            applyNavigationCarryToVisit(visitFromEmptyStages, {
                currentUrl: "https://sway.test/admin/bill_creator/42/pipeline?selected_stages=&run_id=99",
            });

            const resultFromEmpty = visitFromEmptyStages.url as URL;
            expect(resultFromEmpty.searchParams.has("selected_stages")).toBe(false);
            expect(resultFromEmpty.searchParams.has("selected_stages[]")).toBe(false);
            expect(resultFromEmpty.searchParams.has("stages")).toBe(false);
            expect(resultFromEmpty.searchParams.has("stages[]")).toBe(false);
            expect(resultFromEmpty.searchParams.get("run_id")).toBe("99");
        });
    });

    describe("bracketed list parameter handling", () => {
        it("sends a bracketed list parameter with two values, in the spelling qs produces, through a carried navigation and asserts the visit succeeds and both values arrive", () => {
            const visit = {
                url: new URL("https://sway.test/admin/bill_creator/1/pipeline"),
                method: "get",
                data: {},
            } as unknown as PendingVisit;

            applyNavigationCarryToVisit(visit, {
                currentUrl: "https://sway.test/admin/bill_creator/new?stages[]=fetch-bills&stages[]=fetch-law",
            });

            const resultUrl = visit.url as URL;
            expect(resultUrl.searchParams.has("stages[]")).toBe(true);
            const values = resultUrl.searchParams.getAll("stages[]");
            expect(values).toEqual(["fetch-bills", "fetch-law"]);
            expect(resultUrl.search).toBe("?stages%5B%5D=fetch-bills&stages%5B%5D=fetch-law");
        });

        it("does not carry cleared bracketed list parameters and strips them cleanly", () => {
            const destinationUrl = setQueryParamCleared("https://sway.test/admin/bill_creator/1/pipeline", "stages[]");
            expect(destinationUrl).toContain("stages%5B%5D=");

            const visit = {
                url: new URL(destinationUrl),
                method: "get",
                data: {},
            } as unknown as PendingVisit;

            applyNavigationCarryToVisit(visit, {
                currentUrl: "https://sway.test/admin/bill_creator/new?stages[]=fetch-bills&stages[]=fetch-law",
            });

            const resultUrl = visit.url as URL;
            expect(resultUrl.searchParams.has("stages[]")).toBe(false);
            expect(resultUrl.searchParams.has("stages")).toBe(false);
            expect(resultUrl.search).toBe("");
        });
    });

    describe("Inertia router lifecycle integration", () => {
        let originalClient: ReturnType<typeof http.getClient>;
        let lastRequestUrl: string | null = null;

        beforeEach(() => {
            lastRequestUrl = null;
            originalClient = http.getClient();

            registerQueryParamNavigationCarry();

            router.init({
                initialPage: {
                    component: "Bills",
                    props: { errors: {} },
                    url: "/bills",
                    version: "test",
                    clearHistory: false,
                    encryptHistory: false,
                    rescuedProps: [],
                    flash: {},
                    rememberedState: {},
                },
                resolveComponent: async (name: string) => ({ name }),
                swapComponent: async () => {},
            });

            http.setClient({
                request: async (config) => {
                    lastRequestUrl = config.url;
                    return {
                        status: 200,
                        headers: { "x-inertia": "true" },
                        data: JSON.stringify({
                            component: "Bills",
                            props: { errors: {} },
                            url: config.url,
                            version: "test",
                        }),
                    };
                },
            });
        });

        afterEach(() => {
            unregisterQueryParamNavigationCarry();
            router.flushAll();
            http.setClient(originalClient);
        });

        it("isNavigationCarryRegistered returns registration state", () => {
            expect(isNavigationCarryRegistered()).toBe(true);
            unregisterQueryParamNavigationCarry();
            expect(isNavigationCarryRegistered()).toBe(false);
            registerQueryParamNavigationCarry();
            expect(isNavigationCarryRegistered()).toBe(true);
        });

        it("sends a bracketed list parameter with two values through router.visit, visit succeeds, and both values arrive", async () => {
            unregisterQueryParamNavigationCarry();
            registerQueryParamNavigationCarry({
                allowedParameters: ["stages", "stages[]", "sway_locale_id", "run_id"],
                currentUrl: "https://sway.test/bills?stages[]=alpha&stages[]=beta&run_id=88",
            });

            let success = false;
            router.visit("/bills", {
                onSuccess: () => {
                    success = true;
                },
            });

            await new Promise((resolve) => setTimeout(resolve, 50));

            expect(success).toBe(true);
            expect(lastRequestUrl).not.toBeNull();
            const outgoing = new URL(lastRequestUrl!, "https://sway.test");
            expect(outgoing.searchParams.getAll("stages[]")).toEqual(["alpha", "beta"]);
            expect(outgoing.searchParams.get("run_id")).toBe("88");
        });

        it("retains Creator list and scalar controls during router.visit under default production registration", async () => {
            unregisterQueryParamNavigationCarry();
            registerQueryParamNavigationCarry({
                currentUrl:
                    "https://sway.test/admin/bill_creator/42/pipeline?selected_stages[]=fetch-bills&selected_stages[]=fetch-law&download_missing_assets=0&severity=error&window=1d&cursor=cur_123&run_id=99&sway_locale_id=2",
            });

            let success = false;
            router.visit("/admin/bill_creator/42/summary", {
                onSuccess: () => {
                    success = true;
                },
            });

            await new Promise((resolve) => setTimeout(resolve, 50));

            expect(success).toBe(true);
            expect(lastRequestUrl).not.toBeNull();
            const outgoing = new URL(lastRequestUrl!, "https://sway.test");
            expect(outgoing.searchParams.getAll("selected_stages[]")).toEqual(["fetch-bills", "fetch-law"]);
            expect(outgoing.searchParams.get("download_missing_assets")).toBe("0");
            expect(outgoing.searchParams.get("severity")).toBe("error");
            expect(outgoing.searchParams.get("window")).toBe("1d");
            expect(outgoing.searchParams.get("cursor")).toBe("cur_123");
            expect(outgoing.searchParams.get("run_id")).toBe("99");
            expect(outgoing.searchParams.get("sway_locale_id")).toBe("2");
        });

        it("preserves destination parameters and strips cleared parameter via router.visit", async () => {
            unregisterQueryParamNavigationCarry();
            registerQueryParamNavigationCarry({
                currentUrl: "https://sway.test/bills?run_id=42&sway_locale_id=1",
            });

            const clearUrl = setQueryParamCleared("/bills", "run_id");
            expect(clearUrl).toBe("/bills?run_id=");

            let success = false;
            router.visit(clearUrl, {
                onSuccess: () => {
                    success = true;
                },
            });

            await new Promise((resolve) => setTimeout(resolve, 50));

            expect(success).toBe(true);
            expect(lastRequestUrl).not.toBeNull();
            const outgoing = new URL(lastRequestUrl!, "https://sway.test");
            expect(outgoing.searchParams.has("run_id")).toBe(false);
            expect(outgoing.searchParams.get("sway_locale_id")).toBe("1");
        });

        it("excluded route receives zero carried parameters through router.visit", async () => {
            unregisterQueryParamNavigationCarry();
            registerQueryParamNavigationCarry({
                currentUrl: "https://sway.test/bills?run_id=42&sway_locale_id=1",
            });

            let success = false;
            router.visit("/sessions/new", {
                onSuccess: () => {
                    success = true;
                },
            });

            await new Promise((resolve) => setTimeout(resolve, 50));

            expect(success).toBe(true);
            expect(lastRequestUrl).not.toBeNull();
            const outgoing = new URL(lastRequestUrl!, "https://sway.test");
            expect(outgoing.searchParams.has("run_id")).toBe(false);
            expect(outgoing.searchParams.has("sway_locale_id")).toBe(false);
            expect(outgoing.search).toBe("");
        });

        it("prevents foreign legacy aliases from leaking across features during router.visit dispatch (Reproduction 1)", async () => {
            unregisterQueryParamNavigationCarry();
            registerQueryParamNavigationCarry({
                currentUrl: "https://sway.test/bills?search=zoning&sway_locale_id=42",
            });

            let success = false;
            router.visit("/legislators", {
                onSuccess: () => {
                    success = true;
                },
            });

            await new Promise((resolve) => setTimeout(resolve, 50));

            expect(success).toBe(true);
            expect(lastRequestUrl).not.toBeNull();
            const outgoing = new URL(lastRequestUrl!, "https://sway.test");
            expect(outgoing.searchParams.has("search")).toBe(false);
            expect(outgoing.searchParams.has("legislators_search")).toBe(false);
            expect(outgoing.searchParams.get("sway_locale_id")).toBe("42");
        });

        it("ensures explicit destination legacy alias suppresses carried canonical search during router.visit dispatch (Reproduction 2)", async () => {
            unregisterQueryParamNavigationCarry();
            registerQueryParamNavigationCarry({
                currentUrl: "https://sway.test/bills?bills_search=zoning",
            });

            let success = false;
            router.visit("/bills?search=housing", {
                onSuccess: () => {
                    success = true;
                },
            });

            await new Promise((resolve) => setTimeout(resolve, 50));

            expect(success).toBe(true);
            expect(lastRequestUrl).not.toBeNull();
            const outgoing = new URL(lastRequestUrl!, "https://sway.test");
            expect(outgoing.searchParams.get("search")).toBe("housing");
            expect(outgoing.searchParams.has("bills_search")).toBe(false);
        });

        it("preserves destination parameters and does not mutate them when destination explicitly specifies both canonical and alias during router.visit dispatch", async () => {
            unregisterQueryParamNavigationCarry();
            registerQueryParamNavigationCarry({
                currentUrl: "https://sway.test/bills?bills_search=old_carried",
            });

            let success = false;
            router.visit("/bills?bills_search=canonical_choice&search=alias_choice", {
                onSuccess: () => {
                    success = true;
                },
            });

            await new Promise((resolve) => setTimeout(resolve, 50));

            expect(success).toBe(true);
            expect(lastRequestUrl).not.toBeNull();
            const outgoing = new URL(lastRequestUrl!, "https://sway.test");
            expect(outgoing.searchParams.get("bills_search")).toBe("canonical_choice");
            expect(outgoing.searchParams.get("search")).toBe("alias_choice");
        });

        it("cancels router.prefetch when carried query parameters make the prefetch URL identical to the current URL", async () => {
            registerQueryParamNavigationCarry({
                currentUrl: "https://sway.test/past_bills_of_the_month?sway_locale_id=3",
            });

            router.prefetch("/past_bills_of_the_month");

            await new Promise((resolve) => setTimeout(resolve, 50));

            expect(lastRequestUrl).toBeNull();
        });

        it("allows router.prefetch when carried query parameters target a different pathname", async () => {
            unregisterQueryParamNavigationCarry();
            registerQueryParamNavigationCarry({
                currentUrl: "https://sway.test/bills?sway_locale_id=3",
            });

            router.prefetch("/past_bills_of_the_month");

            await new Promise((resolve) => setTimeout(resolve, 50));

            expect(lastRequestUrl).not.toBeNull();
            const outgoing = new URL(lastRequestUrl!, "https://sway.test");
            expect(outgoing.pathname).toBe("/past_bills_of_the_month");
            expect(outgoing.searchParams.get("sway_locale_id")).toBe("3");
        });
    });
});
