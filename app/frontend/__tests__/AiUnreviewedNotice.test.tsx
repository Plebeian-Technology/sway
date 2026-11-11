// @lat: [[bill-summary-reporting#System verification for reader reports and admin triage]]

import { describe, expect, it, vi } from "vitest";
import { fireEvent, render, screen } from "@testing-library/react";

const MOCK_GENERIC_PORTAL_URLS = [
    "https://baltimore.legistar.com",
    "https://baltimore.legistar.com/LegislationSearch.aspx",
    "https://congress.gov",
    "https://www.congress.gov",
    "https://mgaleg.maryland.gov",
    "https://mgaleg.maryland.gov/mgawebsite",
];

vi.mock("@inertiajs/react", () => ({
    usePage: () => ({
        props: {
            user: null,
            sway_locale: {
                generic_portal_urls: MOCK_GENERIC_PORTAL_URLS,
            },
        },
    }),
    useForm: (initial: unknown) => ({
        data: initial,
        setData: vi.fn<() => void>(),
        post: vi.fn<() => void>(),
        reset: vi.fn<() => void>(),
        processing: false,
        errors: {},
    }),
}));

import AiUnreviewedNotice from "app/frontend/components/bill/AiUnreviewedNotice";
import { hasValidSourceLink } from "app/frontend/components/bill/sway_utils/billSourceLink";
import OrgPositionSummary from "app/frontend/components/bill/OrgPositionSummary";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

const NOTICE = PARITY_COPY.bill.aiUnreviewedNotice;

describe("AiUnreviewedNotice", () => {
    it("shows the sentence when the server says nobody has revised the text", () => {
        render(<AiUnreviewedNotice unreviewed={true} />);
        expect(screen.getByTestId("ai-unreviewed-notice").textContent).toBe(NOTICE);
    });

    it("shows nothing when the server says a person wrote the text", () => {
        render(<AiUnreviewedNotice unreviewed={false} />);
        expect(screen.queryByTestId("ai-unreviewed-notice")).toBeNull();
    });

    // The server does not always send the flag — older payloads, and the admin
    // previews that pass nothing. Absent must read as "no notice", never as
    // "unreviewed", or the sentence appears over text no machine wrote.
    it("shows nothing when the server sent no answer at all", () => {
        render(<AiUnreviewedNotice unreviewed={undefined} />);
        expect(screen.queryByTestId("ai-unreviewed-notice")).toBeNull();
    });
});

describe("AiUnreviewedNotice — bill page with report actions", () => {
    it("renders notice bar with report button and link when billId and billLink are passed", () => {
        render(<AiUnreviewedNotice unreviewed={true} billId={101} billLink="https://example.com/bills/101" />);

        expect(screen.getByTestId("ai-summary-notice-bar")).toBeTruthy();
        expect(screen.getByTestId("ai-unreviewed-notice").textContent).toBe(NOTICE);
        expect(screen.getByTestId("btn-report-inaccurate-summary")).toBeTruthy();

        const link = screen.getByTestId("bill-source-text-link");
        expect(link.getAttribute("href")).toBe("https://example.com/bills/101");
        expect(link.getAttribute("target")).toBe("_blank");
    });

    it("clicking report button opens the report dialog", () => {
        render(<AiUnreviewedNotice unreviewed={true} billId={101} billLink="https://example.com/bills/101" />);

        expect(screen.queryByTestId("report-summary-form")).toBeNull();
        fireEvent.click(screen.getByTestId("btn-report-inaccurate-summary"));
        expect(screen.getByTestId("report-summary-form")).toBeTruthy();
    });

    it("renders unavailable notice and report button when unreviewed is false and billLink is missing", () => {
        render(<AiUnreviewedNotice unreviewed={false} billId={101} billLink={null} />);

        expect(screen.getByTestId("ai-summary-notice-bar")).toBeTruthy();
        expect(screen.queryByTestId("ai-unreviewed-notice")).toBeNull();
        expect(screen.queryByTestId("bill-source-text-link")).toBeNull();
        expect(screen.getByTestId("summary-no-source-link")).toBeTruthy();
        expect(screen.getByTestId("summary-no-source-link").textContent).toBe(
            PARITY_COPY.bill.officialSourceUnavailable,
        );
        expect(screen.getByTestId("btn-report-inaccurate-summary")).toBeTruthy();
    });

    it("suppresses source link and renders unavailable notice with report button for generic search URL", () => {
        render(
            <AiUnreviewedNotice
                unreviewed={false}
                billId={101}
                billLink="https://baltimore.legistar.com/LegislationSearch.aspx"
            />,
        );

        expect(screen.getByTestId("ai-summary-notice-bar")).toBeTruthy();
        expect(screen.queryByTestId("ai-unreviewed-notice")).toBeNull();
        expect(screen.queryByTestId("bill-source-text-link")).toBeNull();
        expect(screen.getByTestId("summary-no-source-link")).toBeTruthy();
        expect(screen.getByTestId("summary-no-source-link").textContent).toBe(
            PARITY_COPY.bill.officialSourceUnavailable,
        );
        expect(screen.getByTestId("btn-report-inaccurate-summary")).toBeTruthy();
    });

    it("suppresses source link and renders unavailable notice with report button for generic search URL with query parameters", () => {
        render(
            <AiUnreviewedNotice
                unreviewed={false}
                billId={101}
                billLink="https://baltimore.legistar.com/LegislationSearch.aspx?Mode=Advanced"
            />,
        );

        expect(screen.getByTestId("ai-summary-notice-bar")).toBeTruthy();
        expect(screen.queryByTestId("ai-unreviewed-notice")).toBeNull();
        expect(screen.queryByTestId("bill-source-text-link")).toBeNull();
        expect(screen.getByTestId("summary-no-source-link")).toBeTruthy();
        expect(screen.getByTestId("summary-no-source-link").textContent).toBe(
            PARITY_COPY.bill.officialSourceUnavailable,
        );
        expect(screen.getByTestId("btn-report-inaccurate-summary")).toBeTruthy();
    });

    it("suppresses source link and renders unavailable notice for generic portal URL with trailing slash", () => {
        render(<AiUnreviewedNotice unreviewed={false} billId={101} billLink="https://congress.gov/" />);

        expect(screen.getByTestId("ai-summary-notice-bar")).toBeTruthy();
        expect(screen.queryByTestId("bill-source-text-link")).toBeNull();
        expect(screen.getByTestId("summary-no-source-link")).toBeTruthy();
        expect(screen.getByTestId("summary-no-source-link").textContent).toBe(
            PARITY_COPY.bill.officialSourceUnavailable,
        );
        expect(screen.getByTestId("btn-report-inaccurate-summary")).toBeTruthy();
    });

    it("renders unreviewed notice, unavailable notice, and report button when unreviewed is true and billLink is missing", () => {
        render(<AiUnreviewedNotice unreviewed={true} billId={101} billLink={null} />);

        expect(screen.getByTestId("ai-summary-notice-bar")).toBeTruthy();
        expect(screen.getByTestId("ai-unreviewed-notice").textContent).toBe(NOTICE);
        expect(screen.queryByTestId("bill-source-text-link")).toBeNull();
        expect(screen.getByTestId("summary-no-source-link")).toBeTruthy();
        expect(screen.getByTestId("summary-no-source-link").textContent).toBe(
            PARITY_COPY.bill.officialSourceUnavailable,
        );
        expect(screen.getByTestId("btn-report-inaccurate-summary")).toBeTruthy();
    });

    it("renders source link and report button even when summary was reviewed if billLink is provided", () => {
        render(<AiUnreviewedNotice unreviewed={false} billId={101} billLink="https://example.com/bills/101" />);

        expect(screen.getByTestId("ai-summary-notice-bar")).toBeTruthy();
        expect(screen.queryByTestId("ai-unreviewed-notice")).toBeNull();
        expect(screen.getByTestId("bill-source-text-link")).toBeTruthy();
        expect(screen.getByTestId("btn-report-inaccurate-summary")).toBeTruthy();
    });
});

describe("hasValidSourceLink", () => {
    it("returns false for nil, undefined, and blank strings", () => {
        expect(hasValidSourceLink(null)).toBe(false);
        expect(hasValidSourceLink(undefined)).toBe(false);
        expect(hasValidSourceLink("")).toBe(false);
        expect(hasValidSourceLink("   ")).toBe(false);
    });

    it("returns false for generic search and portal root URLs", () => {
        expect(
            hasValidSourceLink("https://baltimore.legistar.com/LegislationSearch.aspx", MOCK_GENERIC_PORTAL_URLS),
        ).toBe(false);
        expect(
            hasValidSourceLink("https://baltimore.legistar.com/LegislationSearch.aspx/", MOCK_GENERIC_PORTAL_URLS),
        ).toBe(false);
        expect(hasValidSourceLink("https://baltimore.legistar.com", MOCK_GENERIC_PORTAL_URLS)).toBe(false);
        expect(hasValidSourceLink("https://baltimore.legistar.com/", MOCK_GENERIC_PORTAL_URLS)).toBe(false);
        expect(hasValidSourceLink("https://congress.gov", MOCK_GENERIC_PORTAL_URLS)).toBe(false);
        expect(hasValidSourceLink("https://congress.gov/", MOCK_GENERIC_PORTAL_URLS)).toBe(false);
        expect(hasValidSourceLink("https://www.congress.gov", MOCK_GENERIC_PORTAL_URLS)).toBe(false);
        expect(hasValidSourceLink("https://www.congress.gov/", MOCK_GENERIC_PORTAL_URLS)).toBe(false);
        expect(hasValidSourceLink("https://mgaleg.maryland.gov", MOCK_GENERIC_PORTAL_URLS)).toBe(false);
        expect(hasValidSourceLink("https://mgaleg.maryland.gov/", MOCK_GENERIC_PORTAL_URLS)).toBe(false);
        expect(hasValidSourceLink("https://mgaleg.maryland.gov/mgawebsite", MOCK_GENERIC_PORTAL_URLS)).toBe(false);
        expect(hasValidSourceLink("https://mgaleg.maryland.gov/mgawebsite/", MOCK_GENERIC_PORTAL_URLS)).toBe(false);
    });

    it("returns false for generic search and portal URLs with query parameters", () => {
        expect(
            hasValidSourceLink(
                "https://baltimore.legistar.com/LegislationSearch.aspx?Mode=Advanced",
                MOCK_GENERIC_PORTAL_URLS,
            ),
        ).toBe(false);
        expect(hasValidSourceLink("https://congress.gov?query=test", MOCK_GENERIC_PORTAL_URLS)).toBe(false);
        expect(
            hasValidSourceLink("https://mgaleg.maryland.gov/mgawebsite?session=2026", MOCK_GENERIC_PORTAL_URLS),
        ).toBe(false);
    });

    it("returns false for generic search and portal URLs with protocol variations or mixed casing", () => {
        expect(
            hasValidSourceLink("http://baltimore.legistar.com/LegislationSearch.aspx", MOCK_GENERIC_PORTAL_URLS),
        ).toBe(false);
        expect(hasValidSourceLink("http://congress.gov", MOCK_GENERIC_PORTAL_URLS)).toBe(false);
        expect(hasValidSourceLink("https://Congress.gov", MOCK_GENERIC_PORTAL_URLS)).toBe(false);
        expect(
            hasValidSourceLink("https://baltimore.legistar.com/legislationsearch.aspx", MOCK_GENERIC_PORTAL_URLS),
        ).toBe(false);
    });

    it("returns false for malformed strings, relative paths, and non-web protocols", () => {
        expect(hasValidSourceLink("not-a-valid-url")).toBe(false);
        expect(hasValidSourceLink("://bad-url")).toBe(false);
        expect(hasValidSourceLink("/LegislationSearch.aspx")).toBe(false);
        expect(hasValidSourceLink("javascript:alert(1)")).toBe(false);
        expect(hasValidSourceLink("mailto:test@example.com")).toBe(false);
    });

    it("returns true for specific legislation URLs", () => {
        expect(
            hasValidSourceLink(
                "https://baltimore.legistar.com/LegislationDetail.aspx?ID=654321&GUID=FEDCBA",
                MOCK_GENERIC_PORTAL_URLS,
            ),
        ).toBe(true);
        expect(
            hasValidSourceLink("https://www.congress.gov/bill/118th-congress/house-bill/1", MOCK_GENERIC_PORTAL_URLS),
        ).toBe(true);
        expect(
            hasValidSourceLink(
                "https://mgaleg.maryland.gov/mgawebsite/Legislation/Details/hb0001?ys=2024RS",
                MOCK_GENERIC_PORTAL_URLS,
            ),
        ).toBe(true);
    });
});

describe("OrgPositionSummary", () => {
    it("puts the notice under a machine-written position", async () => {
        render(<OrgPositionSummary summary="The model wrote this." summaryAiUnreviewed={true} />);

        expect(await screen.findByText("The model wrote this.")).toBeTruthy();
        expect(screen.getByTestId("ai-unreviewed-notice")).toBeTruthy();
    });

    // The two inputs DISAGREE here: same text, opposite flag. A component that
    // decided from the text instead of the flag would pass the case above and
    // fail this one.
    it("leaves a revised position with no notice", async () => {
        render(<OrgPositionSummary summary="The model wrote this." summaryAiUnreviewed={false} />);

        expect(await screen.findByText("The model wrote this.")).toBeTruthy();
        expect(screen.queryByTestId("ai-unreviewed-notice")).toBeNull();
    });

    it("never stores the sentence inside the text it describes", async () => {
        render(<OrgPositionSummary summary="The model wrote this." summaryAiUnreviewed={true} />);

        // The paragraph holds the position text and nothing else. A notice
        // concatenated into the stored text would show up here, and every
        // other reader of that column would inherit it.
        expect((await screen.findByText("The model wrote this.")).textContent).toBe("The model wrote this.");
    });

    it("keeps the layout's own opening words in front of the text", async () => {
        render(<OrgPositionSummary summary="The model wrote this." summaryAiUnreviewed={true} prefix="In support." />);

        expect(await screen.findByText("The model wrote this.")).toBeTruthy();
        expect(screen.getByText("In support.")).toBeTruthy();
        expect(screen.getByTestId("ai-unreviewed-notice")).toBeTruthy();
    });

    it("renders the position text as markdown", async () => {
        const { container } = render(
            <OrgPositionSummary summary={"**Bold** reason\n\n- first\n- second"} summaryAiUnreviewed={false} />,
        );

        expect((await screen.findByText("Bold")).tagName).toBe("STRONG");
        expect(container.querySelectorAll("li")).toHaveLength(2);
    });

    it("renders nothing at all when there is no position text", () => {
        const { container } = render(<OrgPositionSummary summary={undefined} summaryAiUnreviewed={true} />);

        expect(container.innerHTML).toBe("");
    });

    it("renders nothing for the null a Neutral position is sent as", () => {
        const { container } = render(<OrgPositionSummary summary={null} summaryAiUnreviewed={false} />);

        expect(container.innerHTML).toBe("");
    });
});
