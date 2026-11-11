// @lat: [[query-parameter-navigation-carry#The cleared-on-purpose signal]]

import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { http, router } from "@inertiajs/core";
import {
    isQueryParamCleared,
    registerClearedParamStripPoint,
    setQueryParamCleared,
    stripClearedQueryParams,
    unregisterClearedParamStripPoint,
} from "app/frontend/sway_utils/queryParamClearedSignal";

describe("queryParamClearedSignal", () => {
    describe("setQueryParamCleared", () => {
        it("produces ?param= (empty string value) on a bare path", () => {
            expect(setQueryParamCleared("/bills", "filter")).toBe("/bills?filter=");
        });

        it("produces ?param= on an empty string", () => {
            expect(setQueryParamCleared("", "filter")).toBe("?filter=");
        });

        it("produces /?param= on a root path", () => {
            expect(setQueryParamCleared("/", "filter")).toBe("/?filter=");
        });

        it("replaces an existing parameter value with empty string", () => {
            expect(setQueryParamCleared("/bills?filter=active", "filter")).toBe("/bills?filter=");
        });

        it("preserves other query parameters while clearing the target", () => {
            const result = setQueryParamCleared("/bills?sort=name&filter=active&page=2", "filter");
            expect(result).toContain("sort=name");
            expect(result).toContain("page=2");
            expect(result).toMatch(/[?&]filter=(&|$)/);
            expect(result).not.toContain("filter=active");
        });

        it("preserves hash fragments", () => {
            const result = setQueryParamCleared("/bills?filter=active#section-1", "filter");
            expect(result).toBe("/bills?filter=#section-1");
        });

        it("operates on full URLs", () => {
            const result = setQueryParamCleared("https://sway.test/bills?filter=active&locale=1#top", "filter");
            expect(result).toContain("https://sway.test/bills?");
            expect(result).toContain("locale=1");
            expect(result).toMatch(/[?&]filter=(&|#|$)/);
            expect(result).toContain("#top");
            expect(result).not.toContain("filter=active");
        });

        it("operates on URLSearchParams instances", () => {
            const params = new URLSearchParams("filter=active&sort=name");
            const returned = setQueryParamCleared(params, "filter");
            expect(returned).toBe(params);
            expect(params.get("filter")).toBe("");
            expect(params.get("sort")).toBe("name");
        });

        it("operates on URL instances", () => {
            const url = new URL("https://sway.test/bills?filter=active&sort=name#hash");
            const returned = setQueryParamCleared(url, "filter");
            expect(returned).toBe(url);
            expect(url.searchParams.get("filter")).toBe("");
            expect(url.searchParams.get("sort")).toBe("name");
            expect(url.hash).toBe("#hash");
        });

        it("removes bracketed array spelling when setting plain name cleared", () => {
            const result = setQueryParamCleared(
                "/admin/pipeline?stages%5B%5D=fetch-bills&stages%5B%5D=fetch-law&run_id=1",
                "stages",
            );
            expect(result).not.toContain("stages%5B%5D");
            expect(result).not.toContain("stages[]");
            expect(result).not.toContain("fetch-bills");
            expect(result).toContain("stages=");
            expect(result).toContain("run_id=1");
        });

        it("removes plain name spelling when setting bracketed name cleared", () => {
            const result = setQueryParamCleared("/admin/pipeline?stages=all&run_id=1", "stages[]");
            expect(result).not.toContain("stages=all");
            expect(result).toMatch(/[?&]stages%5B%5D=(&|$)/);
            expect(result).toContain("run_id=1");
        });
    });

    describe("isQueryParamCleared", () => {
        it("returns true when parameter is present with empty string value", () => {
            expect(isQueryParamCleared("/bills?filter=", "filter")).toBe(true);
            expect(isQueryParamCleared("?filter=", "filter")).toBe(true);
            expect(isQueryParamCleared(new URLSearchParams("filter="), "filter")).toBe(true);
            expect(isQueryParamCleared(new URL("https://sway.test/bills?filter="), "filter")).toBe(true);
        });

        it("returns false when parameter is missing", () => {
            expect(isQueryParamCleared("/bills", "filter")).toBe(false);
            expect(isQueryParamCleared("/bills?sort=name", "filter")).toBe(false);
            expect(isQueryParamCleared(new URLSearchParams("sort=name"), "filter")).toBe(false);
            expect(isQueryParamCleared(new URL("https://sway.test/bills"), "filter")).toBe(false);
        });

        it("returns false when parameter holds a non-empty value", () => {
            expect(isQueryParamCleared("/bills?filter=active", "filter")).toBe(false);
            expect(isQueryParamCleared(new URLSearchParams("filter=active"), "filter")).toBe(false);
            expect(isQueryParamCleared(new URL("https://sway.test/bills?filter=active"), "filter")).toBe(false);
        });

        it("handles bracketed and plain spellings interchangeably for generic parameters", () => {
            expect(isQueryParamCleared("/admin?categories%5B%5D=", "categories")).toBe(true);
            expect(isQueryParamCleared("/admin?categories[]=", "categories")).toBe(true);
            expect(isQueryParamCleared("/admin?categories=", "categories[]")).toBe(true);
            expect(isQueryParamCleared("/admin?categories%5B%5D=economy", "categories")).toBe(false);
            expect(isQueryParamCleared("/admin?categories=economy", "categories[]")).toBe(false);
        });

        it("returns false for intentional empty list parameters even when empty", () => {
            expect(isQueryParamCleared("/admin?selected_stages=", "selected_stages")).toBe(false);
            expect(isQueryParamCleared("/admin?selected_stages[]=", "selected_stages")).toBe(false);
            expect(isQueryParamCleared("/admin?stages=", "stages")).toBe(false);
            expect(isQueryParamCleared("/admin?stages[]=", "stages")).toBe(false);
        });
    });

    describe("stripClearedQueryParams", () => {
        it("removes empty parameter leaving bare path", () => {
            expect(stripClearedQueryParams("/bills?filter=")).toBe("/bills");
            expect(stripClearedQueryParams("?filter=")).toBe("");
            expect(stripClearedQueryParams("/?filter=")).toBe("/");
        });

        it("removes all cleared parameters when multiple are cleared", () => {
            expect(stripClearedQueryParams("/bills?a=&b=&c=")).toBe("/bills");
        });

        it("removes cleared parameters while preserving non-cleared parameters with actual values", () => {
            const stripped = stripClearedQueryParams("/bills?a=&active=1&b=&sort=name&c=");
            expect(stripped).toContain("active=1");
            expect(stripped).toContain("sort=name");
            expect(stripped).not.toContain("a=");
            expect(stripped).not.toContain("b=");
            expect(stripped).not.toContain("c=");
        });

        it("preserves URL hash fragment", () => {
            expect(stripClearedQueryParams("/bills?filter=&sort=name#section-2")).toBe("/bills?sort=name#section-2");
            expect(stripClearedQueryParams("/bills?filter=#section-2")).toBe("/bills#section-2");
        });

        it("handles full URLs correctly", () => {
            expect(stripClearedQueryParams("https://sway.test/bills?filter=&sort=name#top")).toBe(
                "https://sway.test/bills?sort=name#top",
            );
            expect(stripClearedQueryParams("https://sway.test/bills?filter=")).toBe("https://sway.test/bills");
        });

        it("operates on URLSearchParams instances", () => {
            const params = new URLSearchParams("a=&b=val&c=");
            const returned = stripClearedQueryParams(params);
            expect(returned).toBe(params);
            expect(params.has("a")).toBe(false);
            expect(params.has("c")).toBe(false);
            expect(params.get("b")).toBe("val");
        });

        it("operates on URL instances", () => {
            const url = new URL("https://sway.test/bills?a=&b=val&c=#hash");
            const returned = stripClearedQueryParams(url);
            expect(returned).toBe(url);
            expect(url.searchParams.has("a")).toBe(false);
            expect(url.searchParams.has("c")).toBe(false);
            expect(url.searchParams.get("b")).toBe("val");
            expect(url.hash).toBe("#hash");
        });

        it("strips bracketed empty parameters and preserves bracketed parameters with values", () => {
            const stripped = stripClearedQueryParams(
                "/admin?tags%5B%5D=&active_stages%5B%5D=fetch-bills&active_stages%5B%5D=fetch-law",
            );
            expect(stripped).not.toMatch(/[?&]tags(%5B%5D|\[\])?=/);
            expect(stripped).toContain("active_stages");
            expect(stripped).toContain("fetch-bills");
            expect(stripped).toContain("fetch-law");
        });

        it("preserves intentional empty list parameters selected_stages= and stages= while stripping generic cleared parameters", () => {
            const stripped = stripClearedQueryParams(
                "/admin/pipeline?selected_stages=&run_id=&search=&stages=&download_missing_assets=",
            );
            expect(stripped).toContain("selected_stages=");
            expect(stripped).toContain("stages=");
            expect(stripped).not.toContain("run_id=");
            expect(stripped).not.toContain("search=");
            expect(stripped).not.toContain("download_missing_assets=");
        });
    });

    describe("Inertia navigation visit integration", () => {
        let originalClient: ReturnType<typeof http.getClient>;
        let lastRequestUrl: string | null = null;

        beforeEach(() => {
            lastRequestUrl = null;
            originalClient = http.getClient();

            registerClearedParamStripPoint();

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
            unregisterClearedParamStripPoint();
            router.flushAll();
            http.setClient(originalClient);
            registerClearedParamStripPoint();
        });

        it("marks a parameter cleared, sends navigation, and outgoing request carries neither the name nor an empty value", async () => {
            const targetUrl = setQueryParamCleared("/bills?sort=name", "sort");
            expect(targetUrl).toBe("/bills?sort=");

            let success = false;
            router.visit(targetUrl, {
                onSuccess: () => {
                    success = true;
                },
            });

            await new Promise((resolve) => setTimeout(resolve, 50));

            expect(success).toBe(true);
            expect(lastRequestUrl).not.toBeNull();
            const outgoing = new URL(lastRequestUrl!, "https://sway.test");
            expect(outgoing.searchParams.has("sort")).toBe(false);
            expect(outgoing.search).toBe("");
        });

        it("covers a list-shaped name in plain and bracketed spellings, asserting visits succeed", async () => {
            const plainClearedUrl = setQueryParamCleared("/bills", "categories");
            expect(plainClearedUrl).toBe("/bills?categories=");

            let plainSuccess = false;
            router.visit(plainClearedUrl, {
                onSuccess: () => {
                    plainSuccess = true;
                },
            });
            await new Promise((resolve) => setTimeout(resolve, 50));

            expect(plainSuccess).toBe(true);
            expect(lastRequestUrl).not.toBeNull();
            let outgoing = new URL(lastRequestUrl!, "https://sway.test");
            expect(outgoing.searchParams.has("categories")).toBe(false);
            expect(outgoing.searchParams.has("categories[]")).toBe(false);

            const bracketClearedUrl = setQueryParamCleared("/bills", "categories[]");
            expect(bracketClearedUrl).toMatch(/\/bills\?categories(%5B%5D|\[\])=/);

            let bracketSuccess = false;
            router.visit(bracketClearedUrl, {
                onSuccess: () => {
                    bracketSuccess = true;
                },
            });
            await new Promise((resolve) => setTimeout(resolve, 50));

            expect(bracketSuccess).toBe(true);
            expect(lastRequestUrl).not.toBeNull();
            outgoing = new URL(lastRequestUrl!, "https://sway.test");
            expect(outgoing.searchParams.has("categories")).toBe(false);
            expect(outgoing.searchParams.has("categories[]")).toBe(false);

            let valuesSuccess = false;
            router.visit("/bills?categories%5B%5D=economy&categories%5B%5D=education", {
                onSuccess: () => {
                    valuesSuccess = true;
                },
            });
            await new Promise((resolve) => setTimeout(resolve, 50));

            expect(valuesSuccess).toBe(true);
            expect(lastRequestUrl).not.toBeNull();
            outgoing = new URL(lastRequestUrl!, "https://sway.test");
            expect(outgoing.searchParams.getAll("categories[]")).toEqual(["economy", "education"]);
        });

        it("retains selected_stages= on outgoing request during router.visit through registered strip point", async () => {
            const targetUrl = "/admin/bill_creator/42/pipeline?selected_stages=&run_id=";

            let success = false;
            router.visit(targetUrl, {
                onSuccess: () => {
                    success = true;
                },
            });

            await new Promise((resolve) => setTimeout(resolve, 50));

            expect(success).toBe(true);
            expect(lastRequestUrl).not.toBeNull();
            const outgoing = new URL(lastRequestUrl!, "https://sway.test");
            expect(outgoing.searchParams.has("selected_stages")).toBe(true);
            expect(outgoing.searchParams.get("selected_stages")).toBe("");
            expect(outgoing.searchParams.has("run_id")).toBe(false);
        });

        it("retains legacy stages= on outgoing request during router.visit through registered strip point", async () => {
            const targetUrl = "/admin/bill_creator/42/pipeline?stages=&search=";

            let success = false;
            router.visit(targetUrl, {
                onSuccess: () => {
                    success = true;
                },
            });

            await new Promise((resolve) => setTimeout(resolve, 50));

            expect(success).toBe(true);
            expect(lastRequestUrl).not.toBeNull();
            const outgoing = new URL(lastRequestUrl!, "https://sway.test");
            expect(outgoing.searchParams.has("stages")).toBe(true);
            expect(outgoing.searchParams.get("stages")).toBe("");
            expect(outgoing.searchParams.has("search")).toBe(false);
        });

        it("mutation check: removing the strip point causes outgoing request to carry the empty value", async () => {
            unregisterClearedParamStripPoint();

            const targetUrl = setQueryParamCleared("/bills?sort=name", "sort");
            expect(targetUrl).toBe("/bills?sort=");

            let success = false;
            router.visit(targetUrl, {
                onSuccess: () => {
                    success = true;
                },
            });
            await new Promise((resolve) => setTimeout(resolve, 50));

            expect(success).toBe(true);
            expect(lastRequestUrl).not.toBeNull();
            const outgoing = new URL(lastRequestUrl!, "https://sway.test");
            expect(outgoing.searchParams.has("sort")).toBe(true);
            expect(outgoing.searchParams.get("sort")).toBe("");
        });
    });
});
