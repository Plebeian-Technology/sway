// @lat: [[query-parameter-namespaces#Decided prefix namespaces]]
// @lat: [[query-parameter-namespaces#Machine-readable registry and lint enforcement]]

import { describe, expect, it } from "vitest";
import {
    FEATURE_ALIAS_MAP,
    FEATURE_QUERY_PARAMETERS,
    GLOBAL_AMBIENT_QUERY_PARAMETERS,
    getAllowedCarryParametersForPath,
    getFeatureForPath,
    getParameterFamily,
    isGlobalAmbientParameter,
    isParameterOwnedByFeature,
    QUERY_PARAMETER_REGISTRY_FOR_PARITY,
} from "app/frontend/sway_constants/queryParameters";

describe("queryParameters registry constants and helpers", () => {
    describe("getFeatureForPath", () => {
        it("identifies bills feature", () => {
            expect(getFeatureForPath("/bills")).toBe("bills");
            expect(getFeatureForPath("/bills/123")).toBe("bills");
            expect(getFeatureForPath("/bills?search=zoning")).toBe("bills");
            expect(getFeatureForPath("/past_bills_of_the_month")).toBe("bills");
        });

        it("identifies bill_creator feature on creator and editing routes", () => {
            expect(getFeatureForPath("/admin/bill_creator/42/pipeline")).toBe("bill_creator");
            expect(getFeatureForPath("/bills/new")).toBe("bill_creator");
            expect(getFeatureForPath("/bills/42/edit")).toBe("bill_creator");
        });

        it("identifies legislators feature", () => {
            expect(getFeatureForPath("/legislators")).toBe("legislators");
            expect(getFeatureForPath("/legislators/123")).toBe("legislators");
        });

        it("identifies notifications feature", () => {
            expect(getFeatureForPath("/notifications")).toBe("notifications");
        });

        it("identifies organizations feature", () => {
            expect(getFeatureForPath("/organizations")).toBe("organizations");
            expect(getFeatureForPath("/public/organizations")).toBe("organizations");
            expect(getFeatureForPath("/organizations/5")).toBe("organizations");
        });

        it("returns null for non-feature paths", () => {
            expect(getFeatureForPath("/")).toBeNull();
            expect(getFeatureForPath("/about")).toBeNull();
            expect(getFeatureForPath("/bill_of_the_month")).toBeNull();
            expect(getFeatureForPath("/sessions/new")).toBeNull();
        });

        it("returns null when more than one feature claims a path", () => {
            const patterns = FEATURE_QUERY_PARAMETERS.bill_creator.routePatterns;
            patterns.push(/^\/bills$/);

            try {
                expect(getFeatureForPath("/bills")).toBeNull();
            } finally {
                patterns.pop();
            }
        });
    });

    describe("isGlobalAmbientParameter", () => {
        it("recognizes global ambient parameters and bracketed forms", () => {
            expect(isGlobalAmbientParameter("sway_locale_id")).toBe(true);
            expect(isGlobalAmbientParameter("run_id")).toBe(true);
            expect(isGlobalAmbientParameter("highlight_bill_id")).toBe(true);
            expect(isGlobalAmbientParameter("sway_locale_id[]")).toBe(true);
            expect(isGlobalAmbientParameter("run_id[]")).toBe(true);
            expect(isGlobalAmbientParameter("highlight_bill_id[]")).toBe(true);
        });

        it("rejects feature-scoped and unknown parameters", () => {
            expect(isGlobalAmbientParameter("search")).toBe(false);
            expect(isGlobalAmbientParameter("bills_search")).toBe(false);
            expect(isGlobalAmbientParameter("tab")).toBe(false);
            expect(isGlobalAmbientParameter("random_param")).toBe(false);
        });
    });

    describe("FEATURE_ALIAS_MAP", () => {
        it("defines alias mappings for all registered features", () => {
            expect(Object.keys(FEATURE_ALIAS_MAP)).toEqual(Object.keys(FEATURE_QUERY_PARAMETERS));
            expect(FEATURE_ALIAS_MAP.bills.bills_search).toEqual(["search"]);
            expect(FEATURE_ALIAS_MAP.legislators.legislators_search).toEqual(["search"]);
            expect(FEATURE_ALIAS_MAP.organizations.org_tab).toEqual(["tab", "tab_key"]);
            expect(FEATURE_ALIAS_MAP.bill_creator.selected_stages).toEqual(["stages"]);
        });
    });

    describe("getParameterFamily", () => {
        it("maps canonical parameter and its legacy aliases to the same semantic family in bills", () => {
            const fromCanonical = getParameterFamily("bills", "bills_search");
            const fromAlias = getParameterFamily("bills", "search");
            expect(fromCanonical).toEqual(["bills_search", "search"]);
            expect(fromAlias).toEqual(["bills_search", "search"]);
        });

        it("supports argument order (name, feature) and (feature, name)", () => {
            expect(getParameterFamily("bills_search", "bills")).toEqual(["bills_search", "search"]);
            expect(getParameterFamily("search", "bills")).toEqual(["bills_search", "search"]);
            expect(getParameterFamily("bills", "bills_search")).toEqual(["bills_search", "search"]);
            expect(getParameterFamily("bills", "search")).toEqual(["bills_search", "search"]);
        });

        it("maps sorting parameters to their family in bills", () => {
            expect(getParameterFamily("bills", "bills_sort")).toEqual(["bills_sort", "sort"]);
            expect(getParameterFamily("bills", "sort")).toEqual(["bills_sort", "sort"]);
            expect(getParameterFamily("bills", "bills_direction")).toEqual(["bills_direction", "direction"]);
            expect(getParameterFamily("bills", "direction")).toEqual(["bills_direction", "direction"]);
            expect(getParameterFamily("bills", "bills_page")).toEqual(["bills_page", "page"]);
            expect(getParameterFamily("bills", "page")).toEqual(["bills_page", "page"]);
            expect(getParameterFamily("bills", "bills_legislative_session_id")).toEqual([
                "bills_legislative_session_id",
                "legislative_session_id",
            ]);
            expect(getParameterFamily("bills", "legislative_session_id")).toEqual([
                "bills_legislative_session_id",
                "legislative_session_id",
            ]);
        });

        it("maps legislators parameters to their family", () => {
            expect(getParameterFamily("legislators", "legislators_search")).toEqual(["legislators_search", "search"]);
            expect(getParameterFamily("legislators", "search")).toEqual(["legislators_search", "search"]);
            expect(getParameterFamily("legislators", "legislators_tab")).toEqual(["legislators_tab", "tab"]);
            expect(getParameterFamily("legislators", "tab")).toEqual(["legislators_tab", "tab"]);
        });

        it("maps multi-alias feature parameters in organizations", () => {
            expect(getParameterFamily("organizations", "org_tab")).toEqual(["org_tab", "tab", "tab_key"]);
            expect(getParameterFamily("organizations", "tab")).toEqual(["org_tab", "tab", "tab_key"]);
            expect(getParameterFamily("organizations", "tab_key")).toEqual(["org_tab", "tab", "tab_key"]);
        });

        it("maps bill creator tab to its legacy alias tab_key", () => {
            expect(getParameterFamily("bill_creator", "bill_creator_tab")).toEqual(["bill_creator_tab", "tab_key"]);
            expect(getParameterFamily("bill_creator", "tab_key")).toEqual(["bill_creator_tab", "tab_key"]);
        });

        it("keeps the picker sort in a canonical-only family", () => {
            expect(getParameterFamily("bill_creator", "bill_creator_sort")).toEqual(["bill_creator_sort"]);
            expect(isParameterOwnedByFeature("bill_creator", "bill_creator_sort")).toBe(true);
        });

        it("maps selected_stages to its legacy alias stages in bill_creator", () => {
            expect(getParameterFamily("bill_creator", "selected_stages")).toEqual(["selected_stages", "stages"]);
            expect(getParameterFamily("bill_creator", "stages")).toEqual(["selected_stages", "stages"]);
            expect(getParameterFamily("selected_stages")).toEqual(["selected_stages", "stages"]);
        });

        it("strips trailing brackets from bracketed parameters", () => {
            expect(getParameterFamily("bills", "bills_search[]")).toEqual(["bills_search", "search"]);
            expect(getParameterFamily("bills", "search[]")).toEqual(["bills_search", "search"]);
        });

        it("infers feature if omitted for uniquely named canonical parameters", () => {
            expect(getParameterFamily("bills_search")).toEqual(["bills_search", "search"]);
            expect(getParameterFamily("legislators_search")).toEqual(["legislators_search", "search"]);
        });

        it("returns single-element array for unmapped or ambient parameters", () => {
            expect(getParameterFamily("bills", "unknown_key")).toEqual(["unknown_key"]);
            expect(getParameterFamily("sway_locale_id")).toEqual(["sway_locale_id"]);
        });
    });

    describe("isParameterOwnedByFeature", () => {
        it("returns true for both canonical parameters and legacy aliases of a feature", () => {
            expect(isParameterOwnedByFeature("bills", "bills_search")).toBe(true);
            expect(isParameterOwnedByFeature("bills", "search")).toBe(true);
            expect(isParameterOwnedByFeature("bills", "bills_sort")).toBe(true);
            expect(isParameterOwnedByFeature("bills", "sort")).toBe(true);
            expect(isParameterOwnedByFeature("bills_search", "bills")).toBe(true);
            expect(isParameterOwnedByFeature("search", "bills")).toBe(true);
        });

        it("returns false for parameters owned by other features", () => {
            expect(isParameterOwnedByFeature("bills", "legislators_search")).toBe(false);
            expect(isParameterOwnedByFeature("bills", "notifications_tab")).toBe(false);
            expect(isParameterOwnedByFeature("legislators", "bills_sort")).toBe(false);
        });
    });

    describe("getAllowedCarryParametersForPath", () => {
        it("restricts GET parameter carry across foreign feature boundaries to global ambient parameters", () => {
            const allowed = getAllowedCarryParametersForPath("/legislators", "/bills", true);
            expect(allowed.has("sway_locale_id")).toBe(true);
            expect(allowed.has("run_id")).toBe(true);
            expect(allowed.has("highlight_bill_id")).toBe(true);
            expect(allowed.has("search")).toBe(false);
            expect(allowed.has("bills_search")).toBe(false);
            expect(allowed.has("legislators_search")).toBe(false);
            expect(allowed.has("tab")).toBe(false);
        });

        it("admits feature parameters and legacy aliases when source and destination share the same feature on GET", () => {
            const allowed = getAllowedCarryParametersForPath("/bills", "/bills?bills_search=zoning", true);
            expect(allowed.has("sway_locale_id")).toBe(true);
            expect(allowed.has("bills_search")).toBe(true);
            expect(allowed.has("search")).toBe(true);
            expect(allowed.has("bills_sort")).toBe(true);
            expect(allowed.has("sort")).toBe(true);
            expect(allowed.has("legislators_search")).toBe(false);
        });

        it("admits destination feature parameters when sourcePath is undefined for backward compatibility", () => {
            const allowed = getAllowedCarryParametersForPath("/bills");
            expect(allowed.has("sway_locale_id")).toBe(true);
            expect(allowed.has("bills_search")).toBe(true);
            expect(allowed.has("search")).toBe(true);
        });

        it("admits both origin and destination parameters on non-GET visits for server redirect echo", () => {
            const allowed = getAllowedCarryParametersForPath("/bills", "/admin/bill_creator/new", false);
            expect(allowed.has("sway_locale_id")).toBe(true);
            expect(allowed.has("bills_search")).toBe(true);
            expect(allowed.has("search")).toBe(true);
            expect(allowed.has("bill_creator_tab")).toBe(true);
            expect(allowed.has("tab_key")).toBe(true);
        });

        it("returns only global ambient parameters when navigating to or from un-featured routes", () => {
            const allowed = getAllowedCarryParametersForPath("/bill_of_the_month", "/bills", true);
            expect(allowed).toEqual(new Set(GLOBAL_AMBIENT_QUERY_PARAMETERS));
        });

        it("does not bleed bills filter, pagination, or session parameters between /bills and /past_bills_of_the_month", () => {
            expect(getAllowedCarryParametersForPath("/past_bills_of_the_month", "/bills", true)).toEqual(
                new Set(GLOBAL_AMBIENT_QUERY_PARAMETERS),
            );
            expect(getAllowedCarryParametersForPath("/bills", "/past_bills_of_the_month", true)).toEqual(
                new Set(GLOBAL_AMBIENT_QUERY_PARAMETERS),
            );

            const samePastBills = getAllowedCarryParametersForPath(
                "/past_bills_of_the_month",
                "/past_bills_of_the_month",
                true,
            );
            expect(samePastBills.has("bills_search")).toBe(true);
            expect(samePastBills.has("bills_page")).toBe(true);
            expect(samePastBills.has("bills_legislative_session_id")).toBe(false);
            expect(samePastBills.has("legislative_session_id")).toBe(false);
        });
    });

    describe("QUERY_PARAMETER_REGISTRY_FOR_PARITY", () => {
        it("exports the canonical family and route-source shape used by the backend parity check", () => {
            expect(QUERY_PARAMETER_REGISTRY_FOR_PARITY.features.bill_creator.parameters).toContain("bill_creator_sort");
            expect(QUERY_PARAMETER_REGISTRY_FOR_PARITY.features.bill_creator.parameter_families).toHaveProperty(
                "bill_creator_sort",
                [],
            );
            expect(QUERY_PARAMETER_REGISTRY_FOR_PARITY.features.bill_creator.route_patterns).toEqual([
                "^/admin/bill_creator",
                "^/bills/new",
                "^/bills/\\d+/edit",
            ]);
            expect(QUERY_PARAMETER_REGISTRY_FOR_PARITY.global_ambient).toEqual([
                "sway_locale_id",
                "run_id",
                "highlight_bill_id",
            ]);
        });
    });
});
