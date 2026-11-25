// @lat: [[mobile-bill-surface-components-design#BillScreenTabs]]
const mockUseSession = jest.fn();
const SIGNED_IN_BOOTSTRAP_USER = { id: 7, invite_url: "https://app.example.test/invite/7/abc" };
let mockBootstrapUser: typeof SIGNED_IN_BOOTSTRAP_USER | null = SIGNED_IN_BOOTSTRAP_USER;

jest.mock("../../src/hooks/useSession", () => ({
    useSession: () => mockUseSession(),
}));
jest.mock("../../src/hooks/useBootstrap", () => ({
    useBootstrap: () => ({
        bootstrap: { current_user: mockBootstrapUser },
    }),
}));
jest.mock("../../src/hooks/useCastUserVote", () => ({
    useCastUserVote: () => ({ submit: jest.fn(async () => ({})), isOnline: true }),
}));
jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn(async () => {}),
    ImpactFeedbackStyle: { Light: "Light" },
}));
jest.mock("expo-clipboard", () => ({ setStringAsync: jest.fn() }));
jest.mock("expo-web-browser", () => ({
    openBrowserAsync: jest.fn(async () => ({ type: "dismiss" })),
}));
const mockPost = jest.fn();
jest.mock("../../src/api/client", () => ({
    apiClient: { post: (...args: unknown[]) => mockPost(...args), get: jest.fn() },
}));

import React from "react";
import { StyleSheet } from "react-native";
import { fireEvent, render, screen, within } from "@testing-library/react-native";
import * as Clipboard from "expo-clipboard";
import * as WebBrowser from "expo-web-browser";

import { BillScreenTabs, type BillScreenTabsProps } from "../../src/components/BillScreenTabs";
import { ThemeProvider } from "../../src/theme/ThemeProvider";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import type { PublicTestimonyCounts } from "../../src/types/bill";

const scoreDistrict = (number: number, forCount: number, againstCount: number) => ({
    bill_score_id: 9,
    district: { name: `MD${number}`, number, region_code: "MD" },
    comparison_suppressed: false,
    for_percent: Math.round((forCount / (forCount + againstCount)) * 100),
    against_percent: 100 - Math.round((forCount / (forCount + againstCount)) * 100),
    at_large: false,
});

const baseProps = (overrides: Partial<BillScreenTabsProps> = {}): BillScreenTabsProps => ({
    bill: {
        id: 42,
        title: "Open Records Act",
        external_id: "HB1234",
        status: "passed",
        summary: "A short Sway summary.",
    },
    sponsor: { full_name: "Alice Q. Sponsor" },
    userVote: null,
    billScore: {
        for_percent: 70,
        against_percent: 30,
        comparison_suppressed: false,
        districts: [scoreDistrict(1, 6, 2), scoreDistrict(2, 4, 3)],
    },
    organizations: [
        {
            id: 1,
            support: "FOR",
            organization: { name: "Supporters Org" },
            summary: "We support this because it improves access.",
        },
    ],
    readerDistricts: [],
    swayLocaleSlug: "baltimore-maryland-united_states",
    isSignedIn: false,
    detailLoaded: true,
    detailError: null,
    onRetry: jest.fn(),
    onVoted: jest.fn(),
    onNavigateToLegislators: jest.fn(),
    onNavigateToBills: jest.fn(),
    heroTestID: "hero",
    summariesTestID: "summaries",
    ...overrides,
});

const renderTabs = (overrides: Partial<BillScreenTabsProps> = {}) =>
    render(
        <ThemeProvider initialMode="light">
            <BillScreenTabs {...baseProps(overrides)} />
        </ThemeProvider>,
    );

const testIDsInOrder = (): string[] =>
    screen.UNSAFE_root.findAll((node: { props: Record<string, unknown> }) => typeof node.props.testID === "string").map(
        (node: { props: Record<string, unknown> }) => node.props.testID as string,
    );

const COUNTS: PublicTestimonyCounts = { total: 6, support: 3, oppose: 2, neutral: 1 };
const BALTIMORE_LEGISTAR_LINK = "https://baltimore.legistar.com/LegislationDetail.aspx?ID=7001&GUID=ABC";

const openVotes = () => fireEvent.press(screen.getByTestId("tab-votes"));
const openSummaries = () => fireEvent.press(screen.getByTestId("tab-summaries"));

describe("BillScreenTabs", () => {
    beforeEach(() => {
        mockUseSession.mockReturnValue({ isAuthenticated: false, loading: false });
        mockBootstrapUser = SIGNED_IN_BOOTSTRAP_USER;
        mockPost.mockReset();
    });

    describe("before the bill detail response has arrived", () => {
        const pending = { detailLoaded: false, billScore: null, organizations: [] };

        test("the Votes tab shows a skeleton, not a zero tally or the district charts", () => {
            renderTabs(pending);
            openVotes();

            expect(screen.getByTestId("votes-skeleton")).toBeTruthy();
            expect(screen.queryByTestId("bill-score-bar")).toBeNull();
            expect(screen.queryByTestId("district-votes-panel")).toBeNull();
            expect(screen.queryByText(/For: 0/)).toBeNull();
            expect(screen.queryByText(PARITY_COPY.bill.noVotesYet)).toBeNull();
            expect(screen.getByTestId("vote-panel")).toBeTruthy();
            expect(screen.getByTestId("take-next-step")).toBeTruthy();
        });

        test("the Summaries tab shows a skeleton, not the claim that no statements were found", () => {
            renderTabs(pending);
            openSummaries();

            expect(screen.getByTestId("summaries-skeleton")).toBeTruthy();
            expect(screen.queryByTestId("org-positions-section")).toBeNull();
            expect(screen.queryByText(PARITY_COPY.org.noSupport)).toBeNull();
        });

        test("the Bill tab still paints from the bill it already has", () => {
            renderTabs(pending);

            expect(screen.getByTestId("hero")).toBeTruthy();
            expect(screen.getByText("Open Records Act")).toBeTruthy();
            expect(screen.getByTestId("bill-summary-section")).toBeTruthy();
            expect(screen.getByTestId("vote-panel")).toBeTruthy();
        });

        test("related news the bill already carries shows above the skeleton", () => {
            renderTabs({
                ...pending,
                bill: {
                    ...baseProps().bill,
                    related_articles: [
                        {
                            id: 10,
                            title: "Transit Overhaul Advances",
                            outlet_name: "The Baltimore Sun",
                            author_name: null,
                            published_at: null,
                            article_kind: "reporting",
                            match_kind: "direct",
                            url: "https://example.com/story",
                        },
                    ],
                },
            });
            openSummaries();

            expect(screen.getByTestId("related-news-articles")).toBeTruthy();
            expect(screen.getByTestId("summaries-skeleton")).toBeTruthy();
        });
    });

    describe("when the detail response failed and nothing has loaded", () => {
        const failed = {
            detailLoaded: false,
            detailError: new Error("boom"),
            billScore: null,
            organizations: [],
        };

        test("the Votes tab offers a retry that calls onRetry", () => {
            const onRetry = jest.fn();
            renderTabs({ ...failed, onRetry });
            openVotes();

            expect(screen.getByTestId("votes-detail-error")).toBeTruthy();
            expect(screen.getByTestId("votes-detail-error").props.className).toContain("py-4");
            expect(screen.getByText(PARITY_COPY.bill.detailError)).toBeTruthy();
            expect(screen.getByText(PARITY_COPY.legislators.historyRetry)).toBeTruthy();
            expect(screen.queryByTestId("votes-skeleton")).toBeNull();
            expect(screen.queryByText(/For: 0/)).toBeNull();

            fireEvent.press(screen.getByTestId("votes-detail-error-cta"));
            expect(onRetry).toHaveBeenCalledTimes(1);
        });

        test("the Summaries tab offers the same retry", () => {
            const onRetry = jest.fn();
            renderTabs({ ...failed, onRetry });
            openSummaries();

            expect(screen.getByTestId("summaries-detail-error")).toBeTruthy();
            expect(screen.getByTestId("summaries-detail-error").props.className).toContain("py-4");
            expect(screen.queryByTestId("org-positions-section")).toBeNull();
            fireEvent.press(screen.getByTestId("summaries-detail-error-cta"));
            expect(onRetry).toHaveBeenCalledTimes(1);
        });

        test("the Bill tab is unaffected", () => {
            renderTabs(failed);
            expect(screen.getByTestId("bill-summary-section")).toBeTruthy();
            expect(screen.queryByTestId("votes-detail-error")).toBeNull();
        });
    });

    describe("once the detail response has arrived", () => {
        test("a failed reload keeps the data on screen instead of a retry row", () => {
            renderTabs({ detailError: new Error("offline") });
            openVotes();
            expect(screen.queryByTestId("votes-detail-error")).toBeNull();
            expect(screen.getByTestId("bill-score-bar")).toBeTruthy();
        });

        test("a bill with no score row says there are not enough votes yet and does not show a skeleton", () => {
            renderTabs({ billScore: null });
            openVotes();

            expect(screen.queryByTestId("votes-skeleton")).toBeNull();
            expect(screen.getByText("Not enough votes yet")).toBeTruthy();
            expect(screen.queryByTestId("district-votes-panel")).toBeNull();
        });

        test("a bill with no organizations still draws the empty positions cards", () => {
            renderTabs({ organizations: [] });
            openSummaries();
            expect(screen.getByText(PARITY_COPY.org.noSupport)).toBeTruthy();
        });
    });

    // @lat: [[voter-privacy-threshold#The mobile bill screen hides what the web hides]]
    describe("the Votes tab below the ten-voter minimum", () => {
        const hiddenScore = {
            for: 6,
            against: 3,
            comparison_suppressed: true,
            voters_needed: 1,
            districts: [scoreDistrict(1, 6, 2)],
        };

        test("shows the placeholder and no count, percentage or district chart", () => {
            renderTabs({ billScore: hiddenScore, readerDistricts: [{ name: "MD1", number: 1, region_code: "MD" }] });
            openVotes();

            expect(screen.getByText("Not enough votes yet")).toBeTruthy();
            expect(screen.getByText("Invite others by sharing Sway")).toBeTruthy();
            expect(screen.queryByTestId("bill-score-bar")).toBeNull();
            expect(screen.queryByTestId("district-votes-panel")).toBeNull();
            expect(screen.queryByText(/For: |Against: |%/)).toBeNull();
            expect(screen.getByTestId("vote-panel")).toBeTruthy();
        });

        test("copies the signed-in reader's invite link", async () => {
            jest.mocked(Clipboard.setStringAsync).mockResolvedValue(true);
            renderTabs({ billScore: hiddenScore, isSignedIn: true });
            openVotes();

            fireEvent.press(screen.getByTestId("vote-comparison-invite"));

            expect(Clipboard.setStringAsync).toHaveBeenCalledWith("https://app.example.test/invite/7/abc");
            expect(await screen.findByText("Invite link copied to clipboard.")).toBeTruthy();
        });

        test("offers a signed-in reader whose bootstrap has not loaded no sign-up button", () => {
            mockBootstrapUser = null;
            renderTabs({ billScore: hiddenScore, isSignedIn: true });
            openVotes();

            expect(screen.getByText("Invite others by sharing Sway")).toBeTruthy();
            expect(screen.queryByTestId("vote-comparison-invite")).toBeNull();
        });

        test("treats a cached payload with no flag as suppressed", () => {
            renderTabs({ billScore: { for: 40, against: 20, districts: [scoreDistrict(1, 30, 10)] } });
            openVotes();

            expect(screen.getByText("Not enough votes yet")).toBeTruthy();
            expect(screen.queryByTestId("bill-score-bar")).toBeNull();
            expect(screen.queryByTestId("district-votes-panel")).toBeNull();
            expect(screen.queryByText(/For: |Against: /)).toBeNull();
        });
    });

    describe("the Votes tab", () => {
        // @lat: [[voter-privacy-threshold#The mobile bill screen hides what the web hides]]
        test("shows the split as percentages and prints no count from the score", () => {
            renderTabs({
                billScore: {
                    for_percent: 70,
                    against_percent: 30,
                    for: 7777,
                    against: 4321,
                    comparison_suppressed: false,
                    districts: [],
                },
            });
            openVotes();

            expect(screen.getByText("For: 70%")).toBeTruthy();
            expect(screen.getByText("Against: 30%")).toBeTruthy();
            expect(screen.queryByText(/7,?777|4,?321/)).toBeNull();
        });

        test("stacks the vote panel, the tally, the districts and the next step in that order", () => {
            renderTabs();
            openVotes();

            const ids = screen.UNSAFE_root.findAll(
                (node: { props: Record<string, unknown> }) => typeof node.props.testID === "string",
            ).map((node: { props: Record<string, unknown> }) => node.props.testID as string);
            const order = ["vote-panel", "bill-score-bar", "district-votes-panel", "take-next-step"].map((id) =>
                ids.indexOf(id),
            );
            order.forEach((position) => expect(position).toBeGreaterThan(-1));
            expect([...order].sort((a, b) => a - b)).toEqual(order);
        });

        test("draws no district section, and no empty slot for one, when the score has no districts", () => {
            renderTabs({
                billScore: { for_percent: 70, against_percent: 30, comparison_suppressed: false, districts: [] },
            });
            openVotes();

            expect(screen.queryByTestId("district-votes-panel")).toBeNull();
            expect(screen.getByTestId("votes-tab-content").children).toHaveLength(3);
        });

        test("draws a slot for the district section when there is one", () => {
            renderTabs();
            openVotes();
            expect(screen.getByTestId("votes-tab-content").children).toHaveLength(4);
        });

        test("shows the tally for a signed-out reader but no reader district", () => {
            renderTabs({ readerDistricts: [{ name: "MD0", number: 0, region_code: "MD" }] });
            openVotes();
            expect(screen.getByTestId("district-votes-panel")).toBeTruthy();
            expect(screen.queryByTestId("district-votes-reader")).toBeNull();
        });

        test("calls out the reader's district and compares it with their vote", () => {
            renderTabs({
                readerDistricts: [{ name: "MD1", number: 1, region_code: "MD" }],
                userVote: { support: "FOR" },
            });
            openVotes();

            expect(screen.getByTestId("district-votes-reader")).toBeTruthy();
            expect(screen.getByTestId("district-votes-alignment")).toHaveTextContent(
                "Your vote matches your district's majority.",
            );
        });

        test("puts no margin above the vote panel inside its card", () => {
            renderTabs();
            openVotes();
            expect(String(screen.getByTestId("vote-panel").props.className ?? "")).not.toMatch(/\bmt-/);
        });
    });

    describe("the Summaries tab", () => {
        test("leaves out the news slot when the bill has no related articles", () => {
            renderTabs();
            openSummaries();
            expect(screen.getByTestId("summaries").children).toHaveLength(1);
        });

        test("shows the public testimony pills under the organization positions for a signed-in reader", () => {
            renderTabs({ isSignedIn: true, publicTestimonyCounts: COUNTS });
            openSummaries();

            expect(screen.getByTestId("public-testimony-section")).toBeTruthy();
            expect(
                screen.getByText(`${COUNTS.support} ${PARITY_COPY.publicTestimony.section.supportPill}`),
            ).toBeTruthy();
            expect(screen.getByText(`${COUNTS.oppose} ${PARITY_COPY.publicTestimony.section.opposePill}`)).toBeTruthy();
            expect(
                screen.getByText(`${COUNTS.neutral} ${PARITY_COPY.publicTestimony.section.neutralPill}`),
            ).toBeTruthy();
            const ids = testIDsInOrder();
            expect(ids.indexOf("public-testimony-section")).toBeGreaterThan(ids.indexOf("org-positions-section"));
            expect(screen.getByTestId("summaries").children).toHaveLength(2);
        });

        test("draws zero nodes, and no empty slot, for a signed-out reader", () => {
            renderTabs({ isSignedIn: false, publicTestimonyCounts: null });
            openSummaries();

            expect(screen.queryByTestId("public-testimony-section")).toBeNull();
            expect(screen.getByTestId("summaries").children).toHaveLength(1);
        });

        test("draws zero nodes even if counts arrive while signed out", () => {
            renderTabs({ isSignedIn: false, publicTestimonyCounts: COUNTS });
            openSummaries();

            expect(screen.queryByTestId("public-testimony-section")).toBeNull();
            expect(screen.getByTestId("summaries").children).toHaveLength(1);
        });

        test("draws zero nodes when a signed-in reader's bill has no letters", () => {
            renderTabs({ isSignedIn: true, publicTestimonyCounts: { total: 0, support: 0, oppose: 0, neutral: 0 } });
            openSummaries();

            expect(screen.queryByTestId("public-testimony-section")).toBeNull();
            expect(screen.getByTestId("summaries").children).toHaveLength(1);
        });

        test("draws zero nodes when the detail response carried no counts", () => {
            renderTabs({ isSignedIn: true, publicTestimonyCounts: undefined });
            openSummaries();

            expect(screen.queryByTestId("public-testimony-section")).toBeNull();
            expect(screen.getByTestId("summaries").children).toHaveLength(1);
        });

        test("keeps the skeleton and draws no testimony slot before the detail response arrives", () => {
            renderTabs({
                detailLoaded: false,
                billScore: null,
                organizations: [],
                isSignedIn: true,
                publicTestimonyCounts: null,
            });
            openSummaries();

            expect(screen.getByTestId("summaries-skeleton")).toBeTruthy();
            expect(screen.queryByTestId("public-testimony-section")).toBeNull();
        });
    });

    describe("the Bill tab", () => {
        test("leaves out the as-introduced slot when the stored title is only the headline", () => {
            renderTabs();
            expect(screen.queryByTestId("bill-as-introduced")).toBeNull();
            expect(screen.getByTestId("bill-tab-content").children).toHaveLength(2);
        });

        test("draws the as-introduced slot, with the deck, for a dashed title that has no legal clause", () => {
            renderTabs({ bill: { ...baseProps().bill, title: "Open Records Act - modernizing public access" } });
            expect(screen.getByTestId("bill-as-introduced")).toBeTruthy();
            expect(screen.getByText("Open Records Act - modernizing public access")).toBeTruthy();
            expect(screen.getByTestId("bill-tab-content").children).toHaveLength(3);
        });

        test("draws the as-introduced slot when the title carries the legal clause", () => {
            renderTabs({
                bill: {
                    ...baseProps().bill,
                    title: "Open Records Act FOR the purpose of requiring agencies to publish their records online",
                },
            });
            expect(screen.getByTestId("bill-as-introduced")).toBeTruthy();
            expect(screen.getByTestId("bill-tab-content").children).toHaveLength(3);
        });

        describe("the vote status sentence", () => {
            const voted = {
                ...baseProps().bill,
                active: true,
                vote_date_time_utc: "2026-03-03T17:00:00Z",
                house_vote_date_time_utc: "2026-03-03T17:00:00Z",
                senate_vote_date_time_utc: null,
            };

            test("sits under the vote buttons inside the hero card, and only once", () => {
                renderTabs({ bill: voted });

                const ids = testIDsInOrder();
                expect(ids.indexOf("bill-header")).toBeGreaterThan(-1);
                expect(ids.indexOf("vote-panel")).toBeGreaterThan(ids.indexOf("bill-header"));
                expect(ids.indexOf("bill-header-vote-status")).toBeGreaterThan(ids.indexOf("vote-panel"));
                expect(screen.getAllByTestId("bill-header-vote-status")).toHaveLength(1);
                expect(within(screen.getByTestId("hero")).getByText("House voted on March 3, 2026.")).toBeTruthy();
            });

            test("says so when no chamber has voted, still under the vote buttons", () => {
                renderTabs({
                    bill: { ...voted, vote_date_time_utc: null, house_vote_date_time_utc: null },
                });

                const ids = testIDsInOrder();
                expect(ids.indexOf("bill-header-vote-status")).toBeGreaterThan(ids.indexOf("vote-panel"));
                expect(screen.getByText(PARITY_COPY.bill.voteStatus.notYetVoted)).toBeTruthy();
            });

            test("warns under the vote buttons when the sponsor may have left office", () => {
                renderTabs({ bill: { ...voted, active: false } });

                const ids = testIDsInOrder();
                expect(ids.indexOf("bill-header-no-longer-in-office")).toBeGreaterThan(ids.indexOf("vote-panel"));
                expect(screen.getAllByTestId("bill-header-no-longer-in-office")).toHaveLength(1);
            });
        });

        describe("the sponsor link", () => {
            const sponsored = { ...baseProps().bill, legislator_id: 7 };

            test("calls onSponsorPress when the bill carries a legislator id and the sponsor has a name", () => {
                const onSponsorPress = jest.fn();
                renderTabs({ bill: sponsored, onSponsorPress });

                fireEvent.press(screen.getByTestId("bill-header-sponsor"));
                expect(onSponsorPress).toHaveBeenCalledTimes(1);
            });

            test("is plain text when the bill has no legislator id", () => {
                renderTabs({ bill: baseProps().bill, onSponsorPress: jest.fn() });

                expect(screen.queryByTestId("bill-header-sponsor")).toBeNull();
                expect(screen.getByText(/Sponsored by Alice Q\. Sponsor/)).toBeTruthy();
            });

            test("is plain text when the legislator id is null", () => {
                renderTabs({ bill: { ...sponsored, legislator_id: null }, onSponsorPress: jest.fn() });

                expect(screen.queryByTestId("bill-header-sponsor")).toBeNull();
            });

            test("is absent when the sponsor has no name", () => {
                renderTabs({ bill: sponsored, sponsor: {}, onSponsorPress: jest.fn() });

                expect(screen.queryByTestId("bill-header-sponsor")).toBeNull();
                expect(screen.queryByText(/Sponsored by/)).toBeNull();
            });

            test("is plain text when the screen offers no handler", () => {
                renderTabs({ bill: sponsored });

                expect(screen.queryByTestId("bill-header-sponsor")).toBeNull();
                expect(screen.getByText(/Sponsored by Alice Q\. Sponsor/)).toBeTruthy();
            });
        });

        describe("the source notice under the summary", () => {
            test("offers the official bill text when the link is on an official host", () => {
                renderTabs({ bill: { ...baseProps().bill, link: BALTIMORE_LEGISTAR_LINK } });

                const notice = screen.getByTestId("bill-summary-notice");
                expect(within(notice).getByText(PARITY_COPY.bill.viewOriginalText)).toBeTruthy();
                expect(screen.queryByTestId("summary-no-source-link")).toBeNull();
            });

            test("opens the link in the in-app browser", () => {
                renderTabs({ bill: { ...baseProps().bill, link: BALTIMORE_LEGISTAR_LINK } });

                fireEvent.press(screen.getByTestId("bill-source-text-link"));
                expect(WebBrowser.openBrowserAsync).toHaveBeenCalledWith(BALTIMORE_LEGISTAR_LINK, expect.anything());
            });

            test("says the source is unavailable when the bill has no link", () => {
                renderTabs({ bill: { ...baseProps().bill, link: null } });

                expect(screen.getByText(PARITY_COPY.bill.officialSourceUnavailable)).toBeTruthy();
                expect(screen.queryByTestId("bill-source-text-link")).toBeNull();
            });

            test("says the source is unavailable when the link is the locale's generic portal page", () => {
                const portal = "https://baltimore.legistar.com/Legislation.aspx";
                renderTabs({
                    bill: { ...baseProps().bill, link: portal },
                    genericPortalUrls: [portal],
                });

                expect(screen.getByText(PARITY_COPY.bill.officialSourceUnavailable)).toBeTruthy();
                expect(screen.queryByTestId("bill-source-text-link")).toBeNull();
            });

            test("says the source is unavailable when the link is not on an official host", () => {
                renderTabs({ bill: { ...baseProps().bill, link: "https://example.com/bills/1" } });

                expect(screen.getByText(PARITY_COPY.bill.officialSourceUnavailable)).toBeTruthy();
                expect(screen.queryByTestId("bill-source-text-link")).toBeNull();
            });

            test("is not drawn on the Votes tab", () => {
                renderTabs({ bill: { ...baseProps().bill, link: BALTIMORE_LEGISTAR_LINK } });
                openVotes();

                expect(screen.queryByTestId("bill-source-text-link")).toBeNull();
                expect(screen.queryByTestId("summary-no-source-link")).toBeNull();
            });
        });

        // @lat: [[bill-summary-reporting#Reader reporting of inaccurate summaries#Reporting from the mobile Bill tab]]
        describe("the report inaccurate summary control", () => {
            const control = () => screen.queryByTestId("btn-report-inaccurate-summary");
            const activeBill = { ...baseProps().bill, active: true };

            test("sits directly under the summary card, before the as-introduced slot", () => {
                renderTabs({
                    isSignedIn: true,
                    bill: { ...activeBill, title: "Open Records Act - modernizing public access" },
                });

                const ids = testIDsInOrder();
                expect(ids.indexOf("btn-report-inaccurate-summary")).toBeGreaterThan(
                    ids.indexOf("bill-summary-section"),
                );
                expect(ids.indexOf("btn-report-inaccurate-summary")).toBeLessThan(ids.indexOf("bill-as-introduced"));
                expect(screen.getByTestId("bill-tab-content").children).toHaveLength(3);
            });

            test("is a button with the shared label and a 44pt tap target", () => {
                renderTabs({ isSignedIn: true, bill: activeBill });

                const button = control();
                expect(button).toBeTruthy();
                expect(button?.props.accessibilityRole).toBe("button");
                expect(button?.props.accessibilityLabel).toBe(PARITY_COPY.bill.reportInaccurateSummary);
                expect(StyleSheet.flatten(button?.props.style).minHeight).toBeGreaterThanOrEqual(44);
                expect(within(button as never).getByText(PARITY_COPY.bill.reportInaccurateSummary)).toBeTruthy();
            });

            test("opens the report sheet for a signed-in reader, and sends nothing until submit", () => {
                renderTabs({ isSignedIn: true, bill: activeBill });
                expect(screen.queryByTestId("report-summary-sheet")).toBeNull();

                fireEvent.press(control() as never);

                expect(screen.getByTestId("report-summary-sheet")).toBeTruthy();
                expect(screen.queryByTestId("report-summary-auth-prompt")).toBeNull();
                expect(mockPost).not.toHaveBeenCalled();
            });

            test("closes the report sheet again with Cancel", () => {
                renderTabs({ isSignedIn: true, bill: activeBill });
                fireEvent.press(control() as never);

                fireEvent.press(screen.getByTestId("report-summary-cancel"));
                expect(screen.queryByTestId("report-summary-sheet")).toBeNull();
            });

            test("sends a guest to the sign-in prompt and sends no request", () => {
                renderTabs({ isSignedIn: false, bill: activeBill });
                expect(screen.queryByTestId("report-summary-auth-prompt")).toBeNull();

                fireEvent.press(control() as never);

                expect(screen.getByTestId("report-summary-auth-prompt")).toBeTruthy();
                const prompt = screen.getByTestId("report-summary-auth-prompt");
                expect(within(prompt).getByText(PARITY_COPY.bill.reportInaccurateSummary)).toBeTruthy();
                expect(within(prompt).getByText(PARITY_COPY.bill.reportDialogDescription)).toBeTruthy();
                expect(screen.getByTestId("btn-auth-prompt-sign-in")).toBeTruthy();
                expect(screen.queryByTestId("report-summary-sheet")).toBeNull();
                expect(mockPost).not.toHaveBeenCalled();
            });

            test("lets a guest dismiss the sign-in prompt", () => {
                renderTabs({ isSignedIn: false, bill: activeBill });
                fireEvent.press(control() as never);

                fireEvent.press(screen.getByTestId("btn-auth-prompt-continue-browsing"));
                expect(screen.queryByTestId("report-summary-auth-prompt")).toBeNull();
            });

            test("is shown when the bill carries no active flag", () => {
                renderTabs({ isSignedIn: true });
                expect(control()).toBeTruthy();
            });

            test("is hidden on an archived historical bill", () => {
                renderTabs({ isSignedIn: true, bill: { ...baseProps().bill, active: false } });
                expect(control()).toBeNull();
            });

            test("is hidden on an archived bill whose release date is null", () => {
                renderTabs({
                    isSignedIn: false,
                    bill: { ...baseProps().bill, active: false, scheduled_release_date_utc: null },
                });
                expect(control()).toBeNull();
            });

            test("is shown on an inactive bill that has a scheduled release date", () => {
                renderTabs({
                    isSignedIn: true,
                    bill: { ...baseProps().bill, active: false, scheduled_release_date_utc: "2026-03-01" },
                });
                expect(control()).toBeTruthy();
            });

            test("is hidden when the bill has no identity", () => {
                renderTabs({ isSignedIn: true, bill: { ...baseProps().bill, id: 0 } });
                expect(control()).toBeNull();
            });

            test("is not drawn on the Votes or Summaries tabs", () => {
                renderTabs({ isSignedIn: true, bill: activeBill });

                openVotes();
                expect(control()).toBeNull();
                openSummaries();
                expect(control()).toBeNull();
            });
        });
    });
});
