// @lat: [[unlinked-bill-presentation#Separation of URL safety from link validity]]

import { describe, expect, it } from "vitest";
import { hasValidSourceLink } from "app/frontend/components/bill/sway_utils/billSourceLink";

describe("hasValidSourceLink", () => {
    const BALTIMORE_PORTALS = [
        "https://baltimore.legistar.com",
        "https://baltimore.legistar.com/legislationsearch.aspx",
    ];

    const CONGRESS_PORTALS = ["https://congress.gov", "https://www.congress.gov"];

    const MARYLAND_PORTALS = ["https://mgaleg.maryland.gov", "https://mgaleg.maryland.gov/mgawebsite"];

    const ALL_PORTALS = [...BALTIMORE_PORTALS, ...CONGRESS_PORTALS, ...MARYLAND_PORTALS];

    describe("filtering against genericPortalUrls", () => {
        it("returns false when link matches configured portal roots", () => {
            expect(hasValidSourceLink("https://baltimore.legistar.com", ALL_PORTALS)).toBe(false);
            expect(hasValidSourceLink("https://baltimore.legistar.com/", ALL_PORTALS)).toBe(false);
            expect(hasValidSourceLink("https://congress.gov", ALL_PORTALS)).toBe(false);
            expect(hasValidSourceLink("https://congress.gov/", ALL_PORTALS)).toBe(false);
            expect(hasValidSourceLink("https://www.congress.gov", ALL_PORTALS)).toBe(false);
            expect(hasValidSourceLink("https://www.congress.gov/", ALL_PORTALS)).toBe(false);
            expect(hasValidSourceLink("https://mgaleg.maryland.gov", ALL_PORTALS)).toBe(false);
            expect(hasValidSourceLink("https://mgaleg.maryland.gov/", ALL_PORTALS)).toBe(false);
        });

        it("returns false when link matches configured search endpoints", () => {
            expect(hasValidSourceLink("https://baltimore.legistar.com/LegislationSearch.aspx", ALL_PORTALS)).toBe(
                false,
            );
            expect(hasValidSourceLink("https://baltimore.legistar.com/legislationsearch.aspx/", ALL_PORTALS)).toBe(
                false,
            );
            expect(hasValidSourceLink("https://mgaleg.maryland.gov/mgawebsite", ALL_PORTALS)).toBe(false);
            expect(hasValidSourceLink("https://mgaleg.maryland.gov/mgawebsite/", ALL_PORTALS)).toBe(false);
        });

        it("returns false for portal links with query parameters", () => {
            expect(
                hasValidSourceLink("https://baltimore.legistar.com/LegislationSearch.aspx?Mode=Advanced", ALL_PORTALS),
            ).toBe(false);
            expect(hasValidSourceLink("https://congress.gov?query=defense", ALL_PORTALS)).toBe(false);
            expect(hasValidSourceLink("https://mgaleg.maryland.gov/mgawebsite?session=2026RS", ALL_PORTALS)).toBe(
                false,
            );
        });

        it("returns false for portal links with protocol variations or mixed casing", () => {
            expect(hasValidSourceLink("http://baltimore.legistar.com/LegislationSearch.aspx", ALL_PORTALS)).toBe(false);
            expect(hasValidSourceLink("http://congress.gov", ALL_PORTALS)).toBe(false);
            expect(hasValidSourceLink("https://CONGRESS.GOV", ALL_PORTALS)).toBe(false);
            expect(hasValidSourceLink("https://Baltimore.Legistar.Com/legislationsearch.aspx", ALL_PORTALS)).toBe(
                false,
            );
        });

        it("handles leading and trailing whitespace in link", () => {
            expect(hasValidSourceLink("  https://baltimore.legistar.com/LegislationSearch.aspx  ", ALL_PORTALS)).toBe(
                false,
            );
            expect(hasValidSourceLink("\thttps://congress.gov\n", ALL_PORTALS)).toBe(false);
        });

        it("filters custom arbitrary jurisdiction portal URLs", () => {
            const customPortals = ["https://annapolis.legistar.com", "https://annapolis.legistar.com/Legislation.aspx"];
            expect(hasValidSourceLink("https://annapolis.legistar.com", customPortals)).toBe(false);
            expect(hasValidSourceLink("https://annapolis.legistar.com/", customPortals)).toBe(false);
            expect(hasValidSourceLink("https://annapolis.legistar.com/Legislation.aspx", customPortals)).toBe(false);
            expect(hasValidSourceLink("https://annapolis.legistar.com/Legislation.aspx?Mode=1", customPortals)).toBe(
                false,
            );
        });
    });

    describe("deep links and valid non-portal URLs", () => {
        it("returns true for specific legislation detail URLs on the same domain", () => {
            expect(
                hasValidSourceLink(
                    "https://baltimore.legistar.com/LegislationDetail.aspx?ID=654321&GUID=FEDCBA",
                    ALL_PORTALS,
                ),
            ).toBe(true);
            expect(hasValidSourceLink("https://www.congress.gov/bill/118th-congress/house-bill/1", ALL_PORTALS)).toBe(
                true,
            );
            expect(
                hasValidSourceLink(
                    "https://mgaleg.maryland.gov/mgawebsite/Legislation/Details/hb0001?ys=2024RS",
                    ALL_PORTALS,
                ),
            ).toBe(true);
            expect(
                hasValidSourceLink("https://annapolis.legistar.com/LegislationDetail.aspx?ID=100", [
                    "https://annapolis.legistar.com",
                ]),
            ).toBe(true);
        });

        it("returns true for valid external URLs unrelated to portal roots", () => {
            expect(hasValidSourceLink("https://example.com/bills/101", ALL_PORTALS)).toBe(true);
            expect(hasValidSourceLink("https://en.wikipedia.org/wiki/Legislation", ALL_PORTALS)).toBe(true);
        });
    });

    describe("invalid and malformed links", () => {
        it("returns false for nil, undefined, and blank strings", () => {
            expect(hasValidSourceLink(null, ALL_PORTALS)).toBe(false);
            expect(hasValidSourceLink(undefined, ALL_PORTALS)).toBe(false);
            expect(hasValidSourceLink("", ALL_PORTALS)).toBe(false);
            expect(hasValidSourceLink("   ", ALL_PORTALS)).toBe(false);
        });

        it("returns false for malformed strings, relative paths, and non-http protocols", () => {
            expect(hasValidSourceLink("not-a-valid-url", ALL_PORTALS)).toBe(false);
            expect(hasValidSourceLink("://bad-url", ALL_PORTALS)).toBe(false);
            expect(hasValidSourceLink("/LegislationSearch.aspx", ALL_PORTALS)).toBe(false);
            expect(hasValidSourceLink("javascript:alert(1)", ALL_PORTALS)).toBe(false);
            expect(hasValidSourceLink("mailto:test@example.com", ALL_PORTALS)).toBe(false);
            expect(hasValidSourceLink("ftp://files.example.com/bill.pdf", ALL_PORTALS)).toBe(false);
        });
    });

    describe("decoupled behavior when genericPortalUrls is empty or undefined", () => {
        it("does not filter portal root URLs when genericPortalUrls is undefined", () => {
            expect(hasValidSourceLink("https://baltimore.legistar.com")).toBe(true);
            expect(hasValidSourceLink("https://congress.gov")).toBe(true);
            expect(hasValidSourceLink("https://mgaleg.maryland.gov")).toBe(true);
        });

        it("does not filter portal root URLs when genericPortalUrls is empty", () => {
            expect(hasValidSourceLink("https://baltimore.legistar.com", [])).toBe(true);
            expect(hasValidSourceLink("https://congress.gov", [])).toBe(true);
            expect(hasValidSourceLink("https://mgaleg.maryland.gov", [])).toBe(true);
        });

        it("ignores malformed or non-string entries in genericPortalUrls without crashing", () => {
            const messyPortals = ["not-a-url", "", "   ", "https://valid-portal.gov"];
            expect(hasValidSourceLink("https://valid-portal.gov", messyPortals)).toBe(false);
            expect(hasValidSourceLink("https://valid-portal.gov/details/1", messyPortals)).toBe(true);
        });
    });
});
